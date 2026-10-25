-- Step 17: withdrawn applicants and students.
--
-- Until now nobody could leave. An applicant who walked away kept a visit slot,
-- and a student who walked away kept a section seat, a pending payment and a
-- place in every queue.
--
-- A withdrawal is recorded on the applicants row (withdrawn_at, withdrawn_by,
-- withdrawn_reason). One function does the whole thing in one transaction:
--   * a booked visit is deleted, with its reschedule requests, so the slot opens
--   * the section seat is deleted, and the next waiting student is seated
--   * a pending payment is deleted (a cleared payment stays: refunds are Finance's)
--   * the student number, slip, COR and cleared payments stay as history
--   * the person gets a notification and the reason goes to the audit log
--
-- Two entry points over one core:
--   withdraw_my_enrollment(reason)           an Applicant or Student, until a COR is issued
--   withdraw_applicant(applicant, reason)    the Registrar or Admin, at any stage
--
-- Nothing here reverses a withdrawal. The columns can only change inside the
-- withdraw function (a trigger refuses any other write, Admin included).
--
-- Existing functions that could hand a withdrawn person a slot, a seat or a COR
-- are replaced below with one added guard each. Each replacement is the latest
-- version of that function plus that guard.

-- withdrawn_by has no foreign key to users on purpose (same as audit_log.actor_id):
-- a second link from applicants to users would make every users(...) embed in the
-- app's queries ambiguous. It holds the users.id of whoever withdrew them.
ALTER TABLE applicants
  ADD COLUMN withdrawn_at     timestamptz NULL,
  ADD COLUMN withdrawn_by     uuid NULL,
  ADD COLUMN withdrawn_reason text NULL,
  ADD CONSTRAINT applicants_withdrawn_together CHECK (
    (withdrawn_at IS NULL AND withdrawn_by IS NULL AND withdrawn_reason IS NULL)
    OR (withdrawn_at IS NOT NULL AND withdrawn_by IS NOT NULL AND withdrawn_reason IS NOT NULL)),
  ADD CONSTRAINT applicants_withdrawn_reason_length CHECK (length(withdrawn_reason) <= 500);

CREATE INDEX idx_applicants_withdrawn ON applicants (withdrawn_at DESC) WHERE withdrawn_at IS NOT NULL;

-- The withdrawal columns change only while withdraw_enrollment_core runs.
CREATE OR REPLACE FUNCTION enforce_withdrawal_columns() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.withdrawing', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NOT NULL OR NEW.withdrawn_reason IS NOT NULL THEN
      RAISE EXCEPTION 'Use the withdraw action to withdraw an applicant';
    END IF;
  ELSIF (NEW.withdrawn_at, NEW.withdrawn_by, NEW.withdrawn_reason)
        IS DISTINCT FROM (OLD.withdrawn_at, OLD.withdrawn_by, OLD.withdrawn_reason) THEN
    RAISE EXCEPTION 'Use the withdraw action to change a withdrawal';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_applicants_withdrawal
  BEFORE INSERT OR UPDATE ON applicants
  FOR EACH ROW EXECUTE FUNCTION enforce_withdrawal_columns();

-- ------------------------------------------------------------
-- The withdrawal
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION withdraw_enrollment_core(p_applicant uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_app     applicants%ROWTYPE;
  v_student uuid;
  v_seats   integer := 0;
  v_message text;
BEGIN
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  -- Two people withdrawing the same applicant queue here; the second finds the
  -- withdrawal already recorded and stops.
  SELECT * INTO v_app FROM applicants WHERE id = p_applicant FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
  END IF;
  IF v_app.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'This enrollment was already withdrawn';
  END IF;

  SELECT id INTO v_student FROM students WHERE applicant_id = v_app.id;

  PERFORM set_config('app.audit_reason', v_reason, true);

  PERFORM set_config('app.withdrawing', 'on', true);
  UPDATE applicants
     SET withdrawn_at = now(), withdrawn_by = current_actor_id(), withdrawn_reason = v_reason
   WHERE id = v_app.id;
  PERFORM set_config('app.withdrawing', '', true);

  -- The visit: only one that is still "booked" holds a slot. An attended or
  -- no_show visit is history and stays. The reschedule requests on the booking
  -- go with it (the audit log keeps them).
  DELETE FROM reschedule_requests
   WHERE booking_id IN (SELECT id FROM visit_bookings WHERE applicant_id = v_app.id AND status = 'booked');
  DELETE FROM visit_bookings WHERE applicant_id = v_app.id AND status = 'booked';

  IF v_student IS NOT NULL THEN
    DELETE FROM payments WHERE student_id = v_student AND status = 'pending';

    DELETE FROM student_sections WHERE student_id = v_student;
    GET DIAGNOSTICS v_seats = ROW_COUNT;
    IF v_seats > 0 THEN
      -- The freed seat goes to the next student waiting for one.
      PERFORM place_waiting_students(v_app.program_id);
    END IF;
  END IF;

  IF v_app.user_id = current_actor_id() THEN
    v_message := 'You withdrew your enrollment. Your visit date and your seat were released. To come back, contact the Registrar.';
  ELSE
    v_message := 'The Registrar withdrew your enrollment. Reason: ' || v_reason;
  END IF;
  INSERT INTO notifications (user_id, kind, title, message, email_status)
  VALUES (v_app.user_id, 'withdrawn', 'Enrollment withdrawn', v_message, 'pending');

  PERFORM set_config('app.audit_reason', '', true);
  RETURN v_app.id;
END;
$$;

CREATE OR REPLACE FUNCTION withdraw_my_enrollment(p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_applicant uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('applicant','student') THEN
    RAISE EXCEPTION 'Only an applicant or student can withdraw their own enrollment';
  END IF;

  v_applicant := my_applicant_id();
  IF v_applicant IS NULL THEN
    RAISE EXCEPTION 'No enrollment found';
  END IF;

  -- Once the COR is issued the enrollment is official: the Registrar records it.
  IF EXISTS (SELECT 1 FROM cors c JOIN students st ON st.id = c.student_id WHERE st.applicant_id = v_applicant) THEN
    RAISE EXCEPTION 'You are already enrolled. Ask the Registrar to withdraw you';
  END IF;

  RETURN withdraw_enrollment_core(v_applicant, p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION withdraw_applicant(p_applicant uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can withdraw an applicant';
  END IF;
  RETURN withdraw_enrollment_core(p_applicant, p_reason);
END;
$$;

REVOKE ALL ON FUNCTION withdraw_enrollment_core(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION withdraw_my_enrollment(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION withdraw_applicant(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION withdraw_my_enrollment(text) TO authenticated;
GRANT EXECUTE ON FUNCTION withdraw_applicant(uuid, text) TO authenticated;

-- ------------------------------------------------------------
-- Guards on existing functions: a withdrawn person is left alone
-- ------------------------------------------------------------

-- A withdrawn applicant cannot be promoted to a student.
CREATE OR REPLACE FUNCTION mark_documents_received(p_applicant uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_app     applicants%ROWTYPE;
  v_missing text;
  v_late    text;
  v_student uuid;
  v_number  varchar;
  v_message text;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can mark documents received';
  END IF;

  -- Two Registrars on the same applicant queue here; the second one then
  -- finds the students row and stops.
  SELECT * INTO v_app FROM applicants WHERE id = p_applicant FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
  END IF;

  IF v_app.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'This applicant has withdrawn';
  END IF;

  IF EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = v_app.id) THEN
    RAISE EXCEPTION 'This applicant is already a student';
  END IF;

  SELECT string_agg(r.label, '; ' ORDER BY r.sort_order) INTO v_missing
  FROM document_requirements r
  WHERE r.active AND r.required
    AND v_app.admission_type = ANY (r.applies_to)
    AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.applicant_id = v_app.id AND d.doc_type = r.doc_type);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot mark documents received. Still missing: %', v_missing;
  END IF;

  SELECT string_agg(r.label, '; ' ORDER BY r.sort_order) INTO v_late
  FROM document_requirements r
  WHERE r.active AND NOT r.required
    AND r.doc_type <> 'other'
    AND v_app.admission_type = ANY (r.applies_to)
    AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.applicant_id = v_app.id AND d.doc_type = r.doc_type);

  INSERT INTO students (applicant_id, documents_received_by)
  VALUES (v_app.id, current_actor_id())
  RETURNING id, student_number INTO v_student, v_number;

  -- Only a booking that is still "booked". An attended or no_show booking stays as it is.
  UPDATE visit_bookings SET status = 'attended'
   WHERE applicant_id = v_app.id AND status = 'booked';

  v_message := 'Your documents were received. Your student number is ' || v_number || '.';
  IF v_late IS NOT NULL THEN
    v_message := v_message || ' Still to submit later: ' || v_late || '.';
  END IF;

  INSERT INTO notifications (user_id, kind, title, message, email_status)
  VALUES (v_app.user_id, 'documents_received', 'Documents received', v_message, 'pending');

  RETURN v_student;
END;
$$;

-- A withdrawn applicant cannot be given a visit slot (covers assign, move and reschedule).
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
  IF EXISTS (SELECT 1 FROM applicants WHERE id = p_applicant AND withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This applicant has withdrawn';
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

-- Automatic assignment on intake skips a withdrawn applicant.
CREATE OR REPLACE FUNCTION auto_assign_visit(p_applicant uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program   uuid;
  v_slot      visit_slots%ROWTYPE;
  v_candidate uuid;
BEGIN
  SELECT program_id INTO v_program FROM applicants WHERE id = p_applicant AND withdrawn_at IS NULL;
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

-- The bulk assignment neither books nor counts a withdrawn applicant.
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
      AND a.withdrawn_at IS NULL
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
    AND NOT EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = a.id)
    AND a.withdrawn_at IS NULL;
END;
$$;

-- A withdrawn student is never seated.
CREATE OR REPLACE FUNCTION place_student_in_section(p_student uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program uuid;
  v_user    uuid;
  v_sec     record;
BEGIN
  IF EXISTS (SELECT 1 FROM student_sections WHERE student_id = p_student) THEN
    RETURN NULL;
  END IF;

  SELECT a.program_id, a.user_id INTO v_program, v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student AND a.withdrawn_at IS NULL;
  IF v_program IS NULL THEN
    RETURN NULL;
  END IF;

  -- Lock candidate sections in a fixed order so two placements cannot deadlock
  -- or both take the last seat.
  FOR v_sec IN
    SELECT sec.id, sec.name, sec.year_level, sec.capacity, p.code
      FROM sections sec JOIN programs p ON p.id = sec.program_id
     WHERE sec.program_id = v_program AND sec.year_level = 1
     ORDER BY sec.name, sec.id
       FOR UPDATE OF sec
  LOOP
    IF (SELECT count(*) FROM student_sections WHERE section_id = v_sec.id) < v_sec.capacity THEN
      INSERT INTO student_sections (student_id, section_id) VALUES (p_student, v_sec.id);
      INSERT INTO notifications (user_id, kind, title, message)
      VALUES (v_user, 'section_placed', 'Your section',
              'You are placed in ' || v_sec.code || ' Year ' || v_sec.year_level || ' - ' || v_sec.name
              || '. Your college is preparing your schedule.');
      RETURN v_sec.id;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

-- A withdrawn student is not waiting for a seat.
CREATE OR REPLACE FUNCTION place_waiting_students(p_program uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r      record;
  v_done integer := 0;
BEGIN
  FOR r IN
    SELECT st.id
      FROM students st JOIN applicants a ON a.id = st.applicant_id
     WHERE a.program_id = p_program
       AND a.withdrawn_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM student_sections ss WHERE ss.student_id = st.id)
     ORDER BY st.documents_received_at, st.id
  LOOP
    EXIT WHEN place_student_in_section(r.id) IS NULL;
    v_done := v_done + 1;
  END LOOP;
  RETURN v_done;
END;
$$;

-- A withdrawn student cannot be moved into a section.
CREATE OR REPLACE FUNCTION move_student_section(p_student uuid, p_section uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role     text := app_role();
  v_program  uuid;
  v_user     uuid;
  v_sec      record;
  v_old      uuid;
  v_reason   text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary, the Dean or Admin can place students in sections';
  END IF;

  SELECT a.program_id, a.user_id INTO v_program, v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = p_student AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;

  SELECT sec.id, sec.name, sec.year_level, sec.program_id, p.code INTO v_sec
    FROM sections sec JOIN programs p ON p.id = sec.program_id
   WHERE sec.id = p_section;
  IF v_sec.id IS NULL THEN
    RAISE EXCEPTION 'Section not found';
  END IF;
  IF v_sec.program_id <> v_program THEN
    RAISE EXCEPTION 'A student can only be placed in a section of their own program';
  END IF;
  IF v_role <> 'admin' AND NOT program_in_my_college(v_program) THEN
    RAISE EXCEPTION 'This student belongs to another college';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips WHERE student_id = p_student) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the section can no longer be changed';
  END IF;

  SELECT section_id INTO v_old FROM student_sections WHERE student_id = p_student FOR UPDATE;
  IF v_old = p_section THEN
    RAISE EXCEPTION 'The student is already in this section';
  END IF;

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', v_reason, true);
  END IF;

  IF v_old IS NULL THEN
    INSERT INTO student_sections (student_id, section_id) VALUES (p_student, p_section);
  ELSE
    UPDATE student_sections SET section_id = p_section WHERE student_id = p_student;
  END IF;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user,
          CASE WHEN v_old IS NULL THEN 'section_placed' ELSE 'section_moved' END,
          CASE WHEN v_old IS NULL THEN 'Your section' ELSE 'Your section has changed' END,
          'You are placed in ' || v_sec.code || ' Year ' || v_sec.year_level || ' - ' || v_sec.name
          || '. Your college is preparing your schedule.');

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;
  RETURN p_section;
END;
$$;

-- A withdrawn student cannot be given a COR.
CREATE OR REPLACE FUNCTION enforce_cor_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slip assessment_slips%ROWTYPE;
  v_term enrollment_term%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue a COR';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = NEW.student_id AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;
  SELECT * INTO v_slip FROM assessment_slips WHERE student_id = NEW.student_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The assessment slip must be issued before the COR';
  END IF;
  IF v_slip.payment_required AND NOT EXISTS (
       SELECT 1 FROM payments WHERE student_id = NEW.student_id AND status = 'cleared') THEN
    RAISE EXCEPTION 'Payment must be cleared before the COR';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them before issuing a COR';
  END IF;
  NEW.school_year := v_term.school_year;
  NEW.semester := v_term.semester;
  NEW.schedule := student_schedule_json(NEW.student_id);
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;

-- The bulk COR issue skips a withdrawn student (otherwise the gate above would stop the whole batch).
CREATE OR REPLACE FUNCTION issue_all_ready_cors(OUT issued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue a COR';
  END IF;

  issued := 0;
  FOR r IN
    SELECT st.id
      FROM students st
      JOIN assessment_slips sl ON sl.student_id = st.id
      JOIN applicants a ON a.id = st.applicant_id
     WHERE a.withdrawn_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM cors c WHERE c.student_id = st.id)
       AND (NOT sl.payment_required
            OR EXISTS (SELECT 1 FROM payments pay WHERE pay.student_id = st.id AND pay.status = 'cleared'))
     ORDER BY st.student_number
  LOOP
    PERFORM issue_cor(r.id);
    issued := issued + 1;
  END LOOP;
END;
$$;
