-- Forward-only follow-up (never edit a merged migration).
-- Automation idea #5: give a new applicant a visit slot at the moment of intake.
--
-- 1. assign_visit_slot_core: the body of assign_visit_slot (as last defined in
--    20261025050000_documents_and_numbering.sql) without the role check. Nobody
--    but the database itself may call it.
-- 2. assign_visit_slot is replaced: same arguments, same role check, same
--    behaviour. It checks the caller, then calls the core.
-- 3. auto_assign_visit(applicant): used by the Admissions intake, which has no
--    signed-in person. Books the earliest open slot with a free seat for the
--    applicant's program and writes the same visit_assigned notification. The
--    booking is recorded as assigned by the system (assigned_by is null).
--    Returns the visit as json, or null when no slot is free (the Registrar's
--    "Assign all unassigned" button stays the exception path). An applicant who
--    is already booked gets that visit back and nothing changes. A student is
--    skipped.
-- 4. Only the service role may call auto_assign_visit.

-- ============================================================
-- 1. Core
-- ============================================================
CREATE OR REPLACE FUNCTION assign_visit_slot_core(p_applicant uuid, p_slot uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user       uuid;
  v_type       text;
  v_slot       visit_slots%ROWTYPE;
  v_booking    visit_bookings%ROWTYPE;
  v_booking_id uuid;
  v_kind       text;
  v_title      text;
  v_window     text;
  v_when       text;
  v_bring      text;
BEGIN
  SELECT user_id, admission_type INTO v_user, v_type FROM applicants WHERE id = p_applicant;
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

  v_bring := document_checklist_text(v_type);
  IF nullif(trim(v_slot.what_to_bring), '') IS NOT NULL THEN
    v_bring := CASE WHEN v_bring IS NULL THEN trim(v_slot.what_to_bring)
                    ELSE v_bring || E'\n\n' || trim(v_slot.what_to_bring) END;
  END IF;

  INSERT INTO notifications (user_id, kind, title, message, office_name, window_label, scheduled_for, what_to_bring)
  VALUES (
    v_user, v_kind, v_title,
    'Please go to ' || v_slot.office_name || ' on ' || v_when || ', ' || v_window || '.',
    v_slot.office_name,
    v_window,
    (v_slot.slot_date + v_slot.start_time) AT TIME ZONE 'Asia/Manila',
    v_bring
  );

  IF nullif(trim(p_reason), '') IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;

  RETURN v_booking_id;
END;
$$;

-- ============================================================
-- 2. assign_visit_slot: role check, then the core
-- ============================================================
CREATE OR REPLACE FUNCTION assign_visit_slot(p_applicant uuid, p_slot uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can assign visits';
  END IF;
  RETURN assign_visit_slot_core(p_applicant, p_slot, p_reason);
END;
$$;

-- ============================================================
-- 3. Automatic assignment for the intake
--    Same slot rules as next_open_slot: open, same program, not yet ended
--    (Manila time), a free seat; earliest date, start time, then office.
--    A few candidates are tried in case another request takes the last seat.
-- ============================================================
CREATE OR REPLACE FUNCTION auto_assign_visit(p_applicant uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program   uuid;
  v_slot      visit_slots%ROWTYPE;
  v_candidate uuid;
BEGIN
  SELECT program_id INTO v_program FROM applicants WHERE id = p_applicant;
  IF v_program IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM students WHERE applicant_id = p_applicant) THEN
    RETURN NULL;
  END IF;

  -- Already booked: report that visit and change nothing.
  SELECT s.* INTO v_slot
    FROM visit_bookings b JOIN visit_slots s ON s.id = b.slot_id
   WHERE b.applicant_id = p_applicant;

  IF v_slot.id IS NULL THEN
    FOR v_candidate IN
      SELECT s.id
        FROM visit_slots s
       WHERE s.program_id = v_program
         AND s.status = 'open'
         AND (s.slot_date + s.end_time) > (now() AT TIME ZONE 'Asia/Manila')
         AND s.capacity > (SELECT count(*) FROM visit_bookings b WHERE b.slot_id = s.id)
       ORDER BY s.slot_date, s.start_time, s.office_name
       LIMIT 5
    LOOP
      BEGIN
        PERFORM assign_visit_slot_core(p_applicant, v_candidate);
        SELECT * INTO v_slot FROM visit_slots WHERE id = v_candidate;
        EXIT;
      EXCEPTION WHEN raise_exception OR unique_violation THEN
        NULL; -- the slot filled up or the applicant was just booked: try the next one
      END;
    END LOOP;
  END IF;

  IF v_slot.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'date',        to_char(v_slot.slot_date, 'YYYY-MM-DD'),
    'start_time',  to_char(v_slot.start_time, 'HH24:MI'),
    'end_time',    to_char(v_slot.end_time, 'HH24:MI'),
    'office_name', v_slot.office_name
  );
END;
$$;

-- ============================================================
-- 4. Who may call them
--    The core has no role check, so only the database may call it.
--    auto_assign_visit has none either, so only the service role may.
-- ============================================================
REVOKE EXECUTE ON FUNCTION assign_visit_slot_core(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auto_assign_visit(uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION assign_visit_slot_core(uuid, uuid, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION auto_assign_visit(uuid) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION assign_visit_slot_core(uuid, uuid, text) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION auto_assign_visit(uuid) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION auto_assign_visit(uuid) TO service_role;
  END IF;
END $$;
