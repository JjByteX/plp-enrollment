-- ============================================================
-- supabase/migrations/20261025120000_reschedules.sql
-- Step 12: reschedules (decision-log.md #5, enrollment-plan.md, Reschedules).
--
-- Forward-only. The mass_reschedules and reschedule_requests tables, their
-- gates, the one-pending-request index and the audit triggers are already in
-- 20261025000000_init.sql; applicants may insert their own request since
-- 20261025020000_.... This adds:
--   - next_open_slot gets two optional arguments, so a day that is being
--     emptied is never chosen as the new date (the one-argument call that
--     assign_unassigned_visits makes still works)
--   - mass_reschedule: one call moves every booked visit on a date (optionally
--     one program or office) to the next open slot, with the reason in the
--     audit log and the visit_moved notification each person already gets
--   - request_reschedule: an applicant or student asks, with a reason
--   - decide_reschedule: the Registrar or Admin approves (moving the visit) or
--     declines with a note, and the person is told
--
-- A reschedule moves the visit only. Only visits still marked booked move;
-- attended and no show stay as they are. Staff cannot pick a target slot in a
-- mass reschedule (target_slot_id stays null); a person who does not fit
-- stays where they are and is counted as left over, so the Registrar adds
-- slots and runs it again.
-- ============================================================

-- ============================================================
-- 1. Next open slot, optionally skipping one date (and one office on it)
--    Written from 20261025040000_visit_scheduling.sql.
-- ============================================================
DROP FUNCTION IF EXISTS next_open_slot(uuid);
CREATE OR REPLACE FUNCTION next_open_slot(
  p_program uuid, p_exclude_date date DEFAULT NULL, p_exclude_office text DEFAULT NULL
) RETURNS uuid
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
    AND NOT (p_exclude_date IS NOT NULL AND s.slot_date = p_exclude_date
             AND (p_exclude_office IS NULL OR s.office_name = p_exclude_office))
  ORDER BY s.slot_date, s.start_time, s.office_name
  LIMIT 1;

  RETURN v_slot;
END;
$$;

-- ============================================================
-- 2. Mass reschedule
--    Affected = booked visits in a slot on p_date, and the program and
--    office when given. Moved in slot-time then admission order, so nobody
--    loses their place. Returns how many moved and how many are left over
--    (no open slot with a free seat on another date).
-- ============================================================
CREATE OR REPLACE FUNCTION mass_reschedule(
  p_date date, p_program uuid, p_office text, p_reason text, OUT moved integer, OUT left_over integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_office text := nullif(btrim(coalesce(p_office, '')), '');
  r        record;
  v_slot   uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can set a mass reschedule';
  END IF;
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'Choose the affected date';
  END IF;
  IF p_date < (now() AT TIME ZONE 'Asia/Manila')::date THEN
    RAISE EXCEPTION 'The affected date cannot be in the past';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM visit_bookings b JOIN visit_slots s ON s.id = b.slot_id
     WHERE b.status = 'booked' AND s.slot_date = p_date
       AND (p_program IS NULL OR s.program_id = p_program)
       AND (v_office IS NULL OR s.office_name = v_office)
  ) THEN
    RAISE EXCEPTION 'No booked visit falls on that date';
  END IF;

  -- The gate trigger sets triggered_by. The row is the record of the event.
  INSERT INTO mass_reschedules (affected_date, program_id, office_name, reason)
  VALUES (p_date, p_program, v_office, v_reason);

  moved := 0;
  left_over := 0;
  FOR r IN
    SELECT b.applicant_id, a.program_id
      FROM visit_bookings b
      JOIN visit_slots s ON s.id = b.slot_id
      JOIN applicants a ON a.id = b.applicant_id
     WHERE b.status = 'booked' AND s.slot_date = p_date
       AND (p_program IS NULL OR s.program_id = p_program)
       AND (v_office IS NULL OR s.office_name = v_office)
     ORDER BY s.start_time, a.admission_date, a.created_at, a.id
  LOOP
    v_slot := next_open_slot(r.program_id, p_date, v_office);
    IF v_slot IS NULL THEN
      left_over := left_over + 1;
      CONTINUE;
    END IF;
    -- Moves the booking, writes the visit_moved notification and puts the
    -- reason in the audit log, all in this transaction.
    PERFORM assign_visit_slot(r.applicant_id, v_slot, 'Mass reschedule: ' || v_reason);
    moved := moved + 1;
  END LOOP;
END;
$$;

-- ============================================================
-- 3. An applicant or student asks to move their visit
-- ============================================================
CREATE OR REPLACE FUNCTION request_reschedule(p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_booking visit_bookings%ROWTYPE;
  v_id      uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('applicant','student') THEN
    RAISE EXCEPTION 'Only an applicant or student can request a reschedule';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  SELECT * INTO v_booking FROM visit_bookings WHERE applicant_id = my_applicant_id() FOR UPDATE;
  IF NOT FOUND OR v_booking.status <> 'booked' THEN
    RAISE EXCEPTION 'You have no booked visit to reschedule';
  END IF;
  IF EXISTS (SELECT 1 FROM reschedule_requests WHERE booking_id = v_booking.id AND status = 'pending') THEN
    RAISE EXCEPTION 'You already have a reschedule request waiting for the Registrar';
  END IF;

  INSERT INTO reschedule_requests (booking_id, requested_by, reason)
  VALUES (v_booking.id, current_actor_id(), v_reason)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 4. The Registrar decides a request
--    Approve: p_slot is the slot to move to, or null for the next open slot
--    on another date than the current one. The visit_moved notification is
--    the answer. Decline: a note is required and the person is told.
-- ============================================================
CREATE OR REPLACE FUNCTION decide_reschedule(
  p_request uuid, p_approve boolean, p_slot uuid, p_note text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_note    text := nullif(btrim(coalesce(p_note, '')), '');
  v_req     reschedule_requests%ROWTYPE;
  v_booking visit_bookings%ROWTYPE;
  v_program uuid;
  v_user    uuid;
  v_current date;
  v_slot    uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can approve or decline a reschedule request';
  END IF;
  IF p_approve IS NULL THEN
    RAISE EXCEPTION 'Approve or decline the request';
  END IF;
  IF v_note IS NOT NULL AND length(v_note) > 500 THEN
    RAISE EXCEPTION 'The note is longer than 500 characters';
  END IF;

  SELECT * INTO v_req FROM reschedule_requests WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'This request has already been decided';
  END IF;

  SELECT * INTO v_booking FROM visit_bookings WHERE id = v_req.booking_id FOR UPDATE;
  SELECT a.program_id, a.user_id INTO v_program, v_user FROM applicants a WHERE a.id = v_booking.applicant_id;

  IF p_approve THEN
    IF v_booking.status <> 'booked' THEN
      RAISE EXCEPTION 'This visit is already marked %, so it cannot be moved', v_booking.status;
    END IF;
    v_slot := p_slot;
    IF v_slot IS NULL THEN
      SELECT slot_date INTO v_current FROM visit_slots WHERE id = v_booking.slot_id;
      v_slot := next_open_slot(v_program, v_current);
      IF v_slot IS NULL THEN
        RAISE EXCEPTION 'No open slot with a free seat is available. Add a slot for this program or choose one';
      END IF;
    END IF;
    PERFORM assign_visit_slot(
      v_booking.applicant_id, v_slot,
      'Reschedule request approved' || coalesce(': ' || v_note, '')
    );
    -- The gate trigger stamps decided_by and decided_at.
    UPDATE reschedule_requests
       SET status = 'approved', new_slot_id = v_slot, decision_note = v_note
     WHERE id = v_req.id;
  ELSE
    IF v_note IS NULL THEN
      RAISE EXCEPTION 'Enter the reason for declining';
    END IF;
    UPDATE reschedule_requests
       SET status = 'declined', decision_note = v_note
     WHERE id = v_req.id;
    INSERT INTO notifications (user_id, kind, title, message)
    VALUES (
      v_user, 'reschedule_declined', 'Your reschedule request was declined',
      'The Registrar declined your request: ' || v_note || ' Your visit date stays the same.'
    );
  END IF;

  RETURN v_req.id;
END;
$$;

-- ============================================================
-- 5. Who may call them. The functions also check the role themselves.
--    request_reschedule stays callable by signed-in people (applicants and
--    students); it refuses every other role itself.
-- ============================================================
REVOKE EXECUTE ON FUNCTION next_open_slot(uuid, date, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION mass_reschedule(date, uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION request_reschedule(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION decide_reschedule(uuid, boolean, uuid, text) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION next_open_slot(uuid, date, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION mass_reschedule(date, uuid, text, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION request_reschedule(text) FROM anon;
    REVOKE EXECUTE ON FUNCTION decide_reschedule(uuid, boolean, uuid, text) FROM anon;
  END IF;
END $$;
