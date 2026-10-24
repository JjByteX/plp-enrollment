-- Forward-only follow-up (never edit a merged migration).
-- Step 6, Visit scheduling. See docs/step-6-visit-scheduling-plan.md.
--
-- 1. visit_slots.what_to_bring (required by the slot form, nullable here).
-- 2. Guard on visit_slots: capacity never below the booked count, a slot
--    with bookings can be closed but not cancelled, and its program,
--    date, time and office cannot change once someone is booked.
-- 3. next_open_slot(program): the earliest open slot with free capacity.
-- 4. assign_visit_slot(applicant, slot, reason): creates or moves the
--    booking and writes the notification in the same transaction.
-- 5. assign_unassigned_visits(program): fills the earliest open slots in
--    order of admission date.
-- 6. Only Registrar and Admin may call them.
--
-- Nothing here sends email. Notifications are written with
-- email_status = 'pending' for the sender that comes later.

-- ============================================================
-- 1. What to bring
-- ============================================================
ALTER TABLE visit_slots ADD COLUMN IF NOT EXISTS what_to_bring text NULL;
COMMENT ON COLUMN visit_slots.what_to_bring IS 'Shown on the applicant''s "Your next step" card and copied into the notification. The slot form requires it; per admission type lists come in step 7.';

-- ============================================================
-- 2. Slot guard
--    Bookings lock the slot row (enforce_booking_capacity), and so does
--    this UPDATE, so the two cannot interleave.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_slot_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booked integer;
BEGIN
  SELECT count(*) INTO v_booked FROM visit_bookings WHERE slot_id = NEW.id;

  IF NEW.capacity < v_booked THEN
    RAISE EXCEPTION 'Capacity cannot be lower than the % applicant(s) already booked', v_booked;
  END IF;

  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' AND v_booked > 0 THEN
    RAISE EXCEPTION 'A slot with bookings cannot be cancelled. Close it, then move the applicants';
  END IF;

  IF NEW.program_id IS DISTINCT FROM OLD.program_id AND v_booked > 0 THEN
    RAISE EXCEPTION 'The program of a slot with bookings cannot be changed';
  END IF;

  -- Changing when or where a booked slot happens would change those
  -- applicants' visit without telling them. Moving people is a reschedule.
  IF v_booked > 0 AND (
       NEW.slot_date   IS DISTINCT FROM OLD.slot_date
    OR NEW.start_time  IS DISTINCT FROM OLD.start_time
    OR NEW.end_time    IS DISTINCT FROM OLD.end_time
    OR NEW.office_name IS DISTINCT FROM OLD.office_name
  ) THEN
    RAISE EXCEPTION 'The date, time and office of a slot with bookings cannot be changed. Close it and move the applicants';
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_visit_slots_guard ON visit_slots;
CREATE TRIGGER trg_visit_slots_guard BEFORE UPDATE ON visit_slots
    FOR EACH ROW EXECUTE FUNCTION enforce_slot_guard();

-- ============================================================
-- 3. Next open slot (reused by the mass reschedule in step 12)
--    Open, same program, not yet ended (Manila time), with a free seat.
--    Earliest date, then earliest start, then office name.
-- ============================================================
CREATE OR REPLACE FUNCTION next_open_slot(p_program uuid) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slot uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can look up visit slots';
  END IF;

  SELECT s.id INTO v_slot
  FROM visit_slots s
  WHERE s.program_id = p_program
    AND s.status = 'open'
    AND (s.slot_date + s.end_time) > (now() AT TIME ZONE 'Asia/Manila')
    AND s.capacity > (SELECT count(*) FROM visit_bookings b WHERE b.slot_id = s.id)
  ORDER BY s.slot_date, s.start_time, s.office_name
  LIMIT 1;

  RETURN v_slot;
END;
$$;

-- ============================================================
-- 4. Assign or move one applicant
--    New booking -> notification kind visit_assigned.
--    Existing booking -> slot_id changes (no new row), kind visit_moved.
--    Capacity, program match and "open" are enforced by the existing
--    trigger on visit_bookings. Any error rolls back the booking and the
--    notification together.
-- ============================================================
CREATE OR REPLACE FUNCTION assign_visit_slot(p_applicant uuid, p_slot uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user       uuid;
  v_slot       visit_slots%ROWTYPE;
  v_booking    visit_bookings%ROWTYPE;
  v_booking_id uuid;
  v_kind       text;
  v_title      text;
  v_window     text;
  v_when       text;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can assign visits';
  END IF;

  SELECT user_id INTO v_user FROM applicants WHERE id = p_applicant;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
  END IF;

  SELECT * INTO v_slot FROM visit_slots WHERE id = p_slot;
  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'Visit slot not found';
  END IF;

  IF nullif(trim(p_reason), '') IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', trim(p_reason), true);
  END IF;

  SELECT * INTO v_booking FROM visit_bookings WHERE applicant_id = p_applicant FOR UPDATE;

  IF v_booking.id IS NULL THEN
    INSERT INTO visit_bookings (slot_id, applicant_id, assigned_by)
    VALUES (p_slot, p_applicant, current_actor_id())
    RETURNING id INTO v_booking_id;
    v_kind  := 'visit_assigned';
    v_title := 'Your visit date';
  ELSE
    IF v_booking.slot_id = p_slot THEN
      RAISE EXCEPTION 'This applicant is already booked into this slot';
    END IF;
    IF v_booking.status <> 'booked' THEN
      RAISE EXCEPTION 'This visit is already marked %, so it cannot be moved', v_booking.status;
    END IF;
    UPDATE visit_bookings
       SET slot_id = p_slot, assigned_by = current_actor_id()
     WHERE id = v_booking.id;
    v_booking_id := v_booking.id;
    v_kind  := 'visit_moved';
    v_title := 'Your visit has been moved';
  END IF;

  v_window := to_char(timestamp '2000-01-01' + v_slot.start_time, 'FMHH12:MI AM')
              || ' to ' ||
              to_char(timestamp '2000-01-01' + v_slot.end_time, 'FMHH12:MI AM');
  v_when   := to_char(v_slot.slot_date, 'FMDay, FMMonth FMDD, YYYY');

  INSERT INTO notifications (user_id, kind, title, message, office_name, window_label, scheduled_for, what_to_bring)
  VALUES (
    v_user, v_kind, v_title,
    'Please go to ' || v_slot.office_name || ' on ' || v_when || ', ' || v_window || '.',
    v_slot.office_name,
    v_window,
    (v_slot.slot_date + v_slot.start_time) AT TIME ZONE 'Asia/Manila',
    v_slot.what_to_bring
  );

  IF nullif(trim(p_reason), '') IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;

  RETURN v_booking_id;
END;
$$;

-- ============================================================
-- 5. Assign all unassigned applicants of one program
--    Order: admission_date, created_at, id. Earliest open slot first.
--    Stops when slots run out and reports how many are left.
--    Applicants who are already students are skipped.
-- ============================================================
CREATE OR REPLACE FUNCTION assign_unassigned_visits(p_program uuid, OUT assigned integer, OUT left_over integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r      record;
  v_slot uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can assign visits';
  END IF;

  assigned := 0;

  FOR r IN
    SELECT a.id
    FROM applicants a
    WHERE a.program_id = p_program
      AND NOT EXISTS (SELECT 1 FROM visit_bookings b WHERE b.applicant_id = a.id)
      AND NOT EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = a.id)
    ORDER BY a.admission_date, a.created_at, a.id
  LOOP
    v_slot := next_open_slot(p_program);
    EXIT WHEN v_slot IS NULL;
    PERFORM assign_visit_slot(r.id, v_slot);
    assigned := assigned + 1;
  END LOOP;

  SELECT count(*)::integer INTO left_over
  FROM applicants a
  WHERE a.program_id = p_program
    AND NOT EXISTS (SELECT 1 FROM visit_bookings b WHERE b.applicant_id = a.id)
    AND NOT EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = a.id);
END;
$$;

-- ============================================================
-- 6. Who may call them. The functions also check the role themselves.
-- ============================================================
REVOKE EXECUTE ON FUNCTION next_open_slot(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION assign_visit_slot(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION assign_unassigned_visits(uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION next_open_slot(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION assign_visit_slot(uuid, uuid, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION assign_unassigned_visits(uuid) FROM anon;
  END IF;
END $$;
