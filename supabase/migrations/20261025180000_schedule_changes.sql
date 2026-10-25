-- ============================================================
-- supabase/migrations/20261025180000_schedule_changes.sql
-- Step 16: schedule changes after the assessment slip.
--
-- Forward-only. Written from:
--   - enforce_slip_gate()                (20261025000000_init.sql)
--   - enforce_cor_gate()                 (20261025110000_cor.sql)
--   - enforce_section_subject_rules()    (20261025070000_section_scheduling.sql)
--   - assessment_slip()                  (20261025090000_laboratory_meetings.sql)
--   - certificate_of_registration()      (20261025110000_cor.sql)
--
-- The slip is the first schedule and the COR is the final one:
--   - Each slip and each COR stores the schedule it was issued with, so an
--     issued document never changes (same idea as the term on a COR).
--   - The Secretary or Dean of the college (and Admin) can change professor,
--     room, day or time of an approved section through amend_schedule, with a
--     required reason, until a student of that section has a COR.
--   - Every placed student gets a notification, and my_schedule_changed()
--     tells the next step card to show one line until their COR exists.
--
-- Existing slips and CORs are filled from the live schedule on the day of
-- this migration. A schedule already edited by SQL cannot be recovered.
-- ============================================================

-- ============================================================
-- 1. One schedule builder
--    The same list the slip has always shown: every meeting, units counted
--    once (the laboratory row shows 0). Internal; nobody calls it directly.
-- ============================================================
CREATE OR REPLACE FUNCTION student_schedule_json(p_student uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'code', sub.code, 'title', sub.title,
           'meeting', ss.meeting,
           'units', CASE WHEN ss.meeting = 'laboratory' THEN 0 ELSE sub.units END,
           'professor', pr.full_name, 'room', r.name,
           'day', ss.day_of_week,
           'start', to_char(ss.start_time, 'HH24:MI'),
           'end', to_char(ss.end_time, 'HH24:MI')
         ) ORDER BY sub.code, (ss.meeting = 'laboratory')), '[]'::jsonb)
    FROM student_sections sts
    JOIN section_subjects ss ON ss.section_id = sts.section_id
    JOIN subjects sub ON sub.id = ss.subject_id
    LEFT JOIN users pr ON pr.id = ss.professor_id
    LEFT JOIN rooms r ON r.id = ss.room_id
   WHERE sts.student_id = p_student
$$;

-- ============================================================
-- 2. The saved copies, backfilled, then required
-- ============================================================
ALTER TABLE assessment_slips ADD COLUMN schedule jsonb NULL;
ALTER TABLE cors ADD COLUMN schedule jsonb NULL;
COMMENT ON COLUMN assessment_slips.schedule IS 'The schedule as it was when the slip was issued. Never changes.';
COMMENT ON COLUMN cors.schedule IS 'The final schedule as it was when the COR was issued. Never changes.';

UPDATE assessment_slips SET schedule = student_schedule_json(student_id) WHERE schedule IS NULL;
UPDATE cors SET schedule = student_schedule_json(student_id) WHERE schedule IS NULL;

ALTER TABLE assessment_slips ALTER COLUMN schedule SET NOT NULL;
ALTER TABLE cors ALTER COLUMN schedule SET NOT NULL;

-- Slip gate: same rules as before, plus the saved schedule.
CREATE OR REPLACE FUNCTION enforce_slip_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_status text;
  v_program uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue an assessment slip';
  END IF;
  SELECT s.schedule_status INTO v_status
    FROM student_sections ss JOIN sections s ON s.id = ss.section_id
    WHERE ss.student_id = NEW.student_id;
  IF v_status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'The student''s schedule must be approved before the assessment slip';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = NEW.student_id;
  NEW.payment_required := coalesce(
    (SELECT payment_required FROM program_payment_settings WHERE program_id = v_program), false);
  NEW.schedule := student_schedule_json(NEW.student_id);
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;

-- COR gate: same rules as before, plus the final schedule.
CREATE OR REPLACE FUNCTION enforce_cor_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slip assessment_slips%ROWTYPE;
  v_term enrollment_term%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue a COR';
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

-- The slip now reads its saved schedule.
CREATE OR REPLACE FUNCTION assessment_slip(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF app_role() IS NULL
     OR (app_role() NOT IN ('registrar','admin') AND p_student IS DISTINCT FROM my_student_id()) THEN
    RAISE EXCEPTION 'You can only view your own assessment slip';
  END IF;

  SELECT jsonb_build_object(
           'studentNumber', st.student_number,
           'fullName', u.full_name,
           'programCode', p.code,
           'programName', p.name,
           'section', p.code || ' Year ' || sec.year_level || ' - ' || sec.name,
           'issuedAt', sl.issued_at,
           'paymentRequired', sl.payment_required,
           'subjects', sl.schedule
         )
    INTO v_result
    FROM assessment_slips sl
    JOIN students st ON st.id = sl.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN student_sections sts ON sts.student_id = st.id
    JOIN sections sec ON sec.id = sts.section_id
   WHERE sl.student_id = p_student;

  RETURN v_result;
END;
$$;

-- The COR now reads its own saved schedule.
CREATE OR REPLACE FUNCTION certificate_of_registration(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF app_role() IS NULL
     OR (app_role() NOT IN ('registrar','admin') AND p_student IS DISTINCT FROM my_student_id()) THEN
    RAISE EXCEPTION 'You can only view your own certificate of registration';
  END IF;

  SELECT jsonb_build_object(
           'studentNumber', st.student_number,
           'fullName', u.full_name,
           'programCode', p.code,
           'programName', p.name,
           'collegeName', col.name,
           'section', p.code || ' Year ' || sec.year_level || ' - ' || sec.name,
           'yearLevel', sec.year_level,
           'admissionType', a.admission_type,
           'schoolYear', c.school_year,
           'semester', c.semester,
           'issuedAt', c.issued_at,
           'issuedByName', iu.full_name,
           'issuedByRole', iu.role,
           'paymentRequired', sl.payment_required,
           'amountDue', pay.amount_due,
           'amountPaid', pay.amount_paid,
           'receiptNo', pay.receipt_no,
           'subjects', c.schedule
         )
    INTO v_result
    FROM cors c
    JOIN students st ON st.id = c.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN colleges col ON col.id = p.college_id
    JOIN assessment_slips sl ON sl.student_id = st.id
    JOIN student_sections sts ON sts.student_id = st.id
    JOIN sections sec ON sec.id = sts.section_id
    JOIN users iu ON iu.id = c.issued_by
    LEFT JOIN payments pay ON pay.student_id = st.id AND pay.status = 'cleared'
   WHERE c.student_id = p_student;

  RETURN v_result;
END;
$$;

-- ============================================================
-- 3. Professor loading rules, replaced
--    Same rules as before. New: on an approved section, an UPDATE of the
--    five loading columns is allowed while amend_schedule has set the
--    transaction-local flag app.amend_schedule. Inserts and deletes stay
--    locked, and so does everything that is not the loading.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_section_subject_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_section uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.section_id ELSE NEW.section_id END;
  v_status  text;
  v_program uuid;
  v_college uuid;
  v_amend   boolean := coalesce(current_setting('app.amend_schedule', true), '') = 'on';
BEGIN
  SELECT s.schedule_status, s.program_id, p.college_id
    INTO v_status, v_program, v_college
    FROM sections s JOIN programs p ON p.id = s.program_id
   WHERE s.id = v_section;
  IF v_status IS DISTINCT FROM 'draft' THEN
    IF NOT (v_amend AND TG_OP = 'UPDATE' AND v_status = 'approved'
            AND (NEW.section_id, NEW.subject_id, NEW.meeting)
                IS NOT DISTINCT FROM (OLD.section_id, OLD.subject_id, OLD.meeting)) THEN
      RAISE EXCEPTION 'The schedule is already submitted; professor loading is locked';
    END IF;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM subjects WHERE id = NEW.subject_id AND program_id = v_program) THEN
      RAISE EXCEPTION 'That subject does not belong to this section''s program';
    END IF;
    IF NEW.professor_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.professor_id AND role = 'professor' AND is_active) THEN
      RAISE EXCEPTION 'Assigned user is not an active Professor';
    END IF;
    IF NEW.room_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM rooms WHERE id = NEW.room_id AND (college_id IS NULL OR college_id = v_college)) THEN
      RAISE EXCEPTION 'That room belongs to another college';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ============================================================
-- 4. Change one subject of an approved section (decision-log.md #28)
--    Secretary or Dean of the section's college, or Admin. Needs a reason.
--    Refused once a student of the section has a COR. The clash rules, the
--    active-professor check and the room-college check still apply (the
--    trigger above and the exclusion constraints). Tells every placed
--    student, and the reason goes into the audit log.
-- ============================================================
CREATE OR REPLACE FUNCTION amend_schedule(
  p_section_subject uuid,
  p_professor uuid,
  p_room uuid,
  p_day smallint,
  p_start time,
  p_end time,
  p_reason text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_reason  text := nullif(trim(coalesce(p_reason, '')), '');
  v_section uuid;
  v_status  text;
  v_college uuid;
  v_label   text;
  v_subject text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary, the Dean or Admin can change an approved schedule';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A reason is required to change an approved schedule';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  SELECT ss.section_id, s.schedule_status, p.college_id,
         p.code || ' Year ' || s.year_level || ' - ' || s.name,
         sub.code || CASE WHEN ss.meeting = 'laboratory' THEN ' Lab' ELSE '' END
    INTO v_section, v_status, v_college, v_label, v_subject
    FROM section_subjects ss
    JOIN sections s ON s.id = ss.section_id
    JOIN programs p ON p.id = s.program_id
    JOIN subjects sub ON sub.id = ss.subject_id
   WHERE ss.id = p_section_subject
     FOR UPDATE OF ss;
  IF v_section IS NULL THEN
    RAISE EXCEPTION 'Subject not found';
  END IF;
  IF v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college THEN
    RAISE EXCEPTION 'This section belongs to another college';
  END IF;
  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved schedule is changed this way; edit a draft schedule directly';
  END IF;
  IF EXISTS (SELECT 1 FROM cors c JOIN student_sections sts ON sts.student_id = c.student_id
              WHERE sts.section_id = v_section) THEN
    RAISE EXCEPTION 'A COR was already issued to a student in this section, so its schedule can no longer be changed';
  END IF;

  PERFORM set_config('app.amend_schedule', 'on', true);
  PERFORM set_config('app.audit_reason', v_reason, true);
  UPDATE section_subjects
     SET professor_id = p_professor,
         room_id = p_room,
         day_of_week = p_day,
         start_time = p_start,
         end_time = p_end
   WHERE id = p_section_subject;
  PERFORM set_config('app.amend_schedule', '', true);
  PERFORM set_config('app.audit_reason', '', true);

  INSERT INTO notifications (user_id, kind, title, message)
  SELECT a.user_id, 'schedule_changed', 'Your schedule changed',
         v_subject || ' in ' || v_label || ' was changed. Your COR will show the final schedule.'
    FROM student_sections sts
    JOIN students st ON st.id = sts.student_id
    JOIN applicants a ON a.id = st.applicant_id
   WHERE sts.section_id = v_section;
END;
$$;

-- ============================================================
-- 5. The signed-in student's own flag
--    True when the schedule saved on their slip differs from the current
--    one and they have no COR yet. False for anyone who is not a student.
-- ============================================================
CREATE OR REPLACE FUNCTION my_schedule_changed() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((
    SELECT sl.schedule IS DISTINCT FROM student_schedule_json(sl.student_id)
           AND NOT EXISTS (SELECT 1 FROM cors c WHERE c.student_id = sl.student_id)
      FROM assessment_slips sl
     WHERE sl.student_id = my_student_id()
  ), false)
$$;

-- ============================================================
-- 6. Who may call them. The earlier grant migration
--    (20261025170000_grant_function_access.sql) lists names, so new
--    functions are granted here. The builder is internal.
-- ============================================================
REVOKE EXECUTE ON FUNCTION student_schedule_json(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION amend_schedule(uuid, uuid, uuid, smallint, time, time, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION my_schedule_changed() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION student_schedule_json(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION amend_schedule(uuid, uuid, uuid, smallint, time, time, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION my_schedule_changed() FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION student_schedule_json(uuid) FROM authenticated;
    GRANT EXECUTE ON FUNCTION amend_schedule(uuid, uuid, uuid, smallint, time, time, text) TO authenticated;
    GRANT EXECUTE ON FUNCTION my_schedule_changed() TO authenticated;
  END IF;
END $$;
