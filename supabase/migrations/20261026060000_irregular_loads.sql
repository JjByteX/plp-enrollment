-- ============================================================
-- supabase/migrations/20261026060000_irregular_loads.sql
-- Step 22: irregular loads.
--
-- Forward-only. Written from docs/step-18-returning-students-plan.md, decision L and step 22.
--
--   - student_subjects: the subject list of one enrollment (one student in one term). Each row
--     is one meeting (lecture or laboratory) of a section subject. A row has a source:
--     'section' (copied from the student's section by the database) or 'added' (a retake or
--     back subject the Secretary or Dean added from another section).
--   - A regular student's list is copied from their section automatically, when they are
--     enrolled, when they move to another section and when a subject is added to the section
--     later. A subject with a prerequisite the student has not passed is left out.
--   - add_subject_to_load / remove_subject_from_load / student_load: the load builder. A subject
--     is added from any section of the current term that offers it. Refused, for every role, when
--     a prerequisite is not passed, the subject is already passed, it is not offered this term
--     (so a 1st semester subject cannot be added in a 2nd semester term), the section has no free
--     seat for that subject, it clashes in time, or the assessment slip was already issued.
--   - Replaced, each written from its latest version so that it reads the per-student list:
--     student_schedule_json (each row also names its own section), enforce_slip_gate,
--     slip_ready_students (a slip needs every section of the load approved), amend_schedule (tells
--     everyone who takes the section subject), professor_class_lists, grade_sections, grade_sheet,
--     save_grades, submit_grades, term_missing_sheets and close_term.
--
-- Seats: a section's capacity still limits how many students are placed in it. An added subject
-- counts the students who take that subject in that section, so one subject can fill up on its own.
--
-- Writes to student_subjects go through the database's own functions. A trigger refuses any other
-- insert or update, Admin included, so a blocked subject cannot be added by hand. Deleting an
-- enrollment removes its list (a withdrawal). Everything is audited like the other tables.
-- ============================================================

-- ============================================================
-- 1. The table
-- ============================================================
CREATE TABLE student_subjects (
    student_id          uuid NOT NULL,
    school_year         text NOT NULL,
    semester            text NOT NULL,
    section_subject_id  uuid NOT NULL REFERENCES section_subjects (id) ON DELETE CASCADE,
    source              text NOT NULL CHECK (source IN ('section','added')),
    added_by            uuid NULL REFERENCES users (id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (student_id, school_year, semester, section_subject_id),
    FOREIGN KEY (student_id, school_year, semester)
        REFERENCES student_sections (student_id, school_year, semester) ON DELETE CASCADE
);
CREATE INDEX idx_student_subjects_section_subject ON student_subjects (section_subject_id);
COMMENT ON TABLE student_subjects IS 'The subject list of one enrollment: one row per meeting of a section subject the student takes. source section = copied from the student''s section, added = a retake or back subject.';

CREATE OR REPLACE FUNCTION refuse_direct_load_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.load_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'A student''s subjects change only through the load builder';
  END IF;
  RETURN NEW;
END;
$$;
-- Inserts and updates only: deleting an enrollment removes its list through the foreign key.
CREATE TRIGGER trg_load_write_guard BEFORE INSERT OR UPDATE ON student_subjects
    FOR EACH ROW EXECUTE FUNCTION refuse_direct_load_write();
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON student_subjects
    FOR EACH ROW EXECUTE FUNCTION log_audit();
ALTER TABLE student_subjects ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_all ON student_subjects FOR ALL TO authenticated
    USING (app_role() = 'admin') WITH CHECK (app_role() = 'admin');

-- ============================================================
-- 2. Small helpers (internal)
-- ============================================================
-- Does the student take this subject in this section (any meeting)?
CREATE OR REPLACE FUNCTION in_section_subject(p_student uuid, p_section uuid, p_subject uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM student_subjects ls
      JOIN section_subjects x ON x.id = ls.section_subject_id
     WHERE ls.student_id = p_student AND x.section_id = p_section AND x.subject_id = p_subject)
$$;

-- A section's subjects copied into a student's list, minus any with an unpassed prerequisite.
CREATE OR REPLACE FUNCTION copy_section_load(p_student uuid, p_section uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM set_config('app.load_write', 'on', true);
  INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source)
  SELECT p_student, sec.school_year, sec.semester, x.id, 'section'
    FROM section_subjects x
    JOIN sections sec ON sec.id = x.section_id
   WHERE x.section_id = p_section
     AND NOT EXISTS (SELECT 1 FROM student_blocking_prerequisites(p_student, x.subject_id))
  ON CONFLICT DO NOTHING;
  PERFORM set_config('app.load_write', 'off', true);
END;
$$;

-- ============================================================
-- 3. Keeping the list in step with the enrollment and the section
-- ============================================================
CREATE OR REPLACE FUNCTION load_after_enrollment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- A move to another section: the section's rows are replaced, added subjects stay.
    DELETE FROM student_subjects
     WHERE student_id = NEW.student_id AND school_year = NEW.school_year AND semester = NEW.semester
       AND source = 'section';
  END IF;
  PERFORM copy_section_load(NEW.student_id, NEW.section_id);
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_load_after_enroll AFTER INSERT ON student_sections
    FOR EACH ROW EXECUTE FUNCTION load_after_enrollment();
CREATE TRIGGER trg_load_after_move AFTER UPDATE OF section_id ON student_sections
    FOR EACH ROW WHEN (OLD.section_id IS DISTINCT FROM NEW.section_id)
    EXECUTE FUNCTION load_after_enrollment();

-- A subject that reaches a section later (added to the catalog, or a laboratory row) reaches the
-- students already in it.
CREATE OR REPLACE FUNCTION load_after_section_subject() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM set_config('app.load_write', 'on', true);
  INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source)
  SELECT ss.student_id, ss.school_year, ss.semester, NEW.id, 'section'
    FROM student_sections ss
   WHERE ss.section_id = NEW.section_id
     AND NOT EXISTS (SELECT 1 FROM student_blocking_prerequisites(ss.student_id, NEW.subject_id))
  ON CONFLICT DO NOTHING;
  PERFORM set_config('app.load_write', 'off', true);
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_load_after_section_subject AFTER INSERT ON section_subjects
    FOR EACH ROW EXECUTE FUNCTION load_after_section_subject();

-- Existing enrollments get the rows of their section.
SELECT set_config('app.load_write', 'on', true);
INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source)
SELECT ss.student_id, ss.school_year, ss.semester, x.id, 'section'
  FROM student_sections ss
  JOIN section_subjects x ON x.section_id = ss.section_id;
SELECT set_config('app.load_write', 'off', true);

-- ============================================================
-- 4. Everything that read "the section's subjects" reads the list
-- ============================================================
-- (from 20261026010000_terms_foundation.sql) Each row also names its own section, so a retake
-- from another section shows where it is taken.
CREATE OR REPLACE FUNCTION student_schedule_json(p_student uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'code', sub.code, 'title', sub.title,
           'meeting', ss.meeting,
           'units', CASE WHEN ss.meeting = 'laboratory' THEN 0 ELSE sub.units END,
           'section', pr.code || ' ' || sec.year_level || sec.name,
           'professor', pu.full_name, 'room', r.name,
           'day', ss.day_of_week,
           'start', to_char(ss.start_time, 'HH24:MI'),
           'end', to_char(ss.end_time, 'HH24:MI')
         ) ORDER BY sub.code, (ss.meeting = 'laboratory')), '[]'::jsonb)
    FROM student_enrollment(p_student) sts
    JOIN student_subjects ls ON ls.student_id = sts.student_id
                            AND ls.school_year = sts.school_year AND ls.semester = sts.semester
    JOIN section_subjects ss ON ss.id = ls.section_subject_id
    JOIN sections sec ON sec.id = ss.section_id
    JOIN programs pr ON pr.id = sec.program_id
    JOIN subjects sub ON sub.id = ss.subject_id
    LEFT JOIN users pu ON pu.id = ss.professor_id
    LEFT JOIN rooms r ON r.id = ss.room_id
$$;

-- A load is ready for the slip when it has subjects and every section it draws from is approved.
CREATE OR REPLACE FUNCTION student_load_ready(p_student uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
           SELECT 1 FROM student_enrollment(p_student) e
             JOIN student_subjects ls ON ls.student_id = e.student_id
                                     AND ls.school_year = e.school_year AND ls.semester = e.semester)
     AND NOT EXISTS (
           SELECT 1 FROM student_enrollment(p_student) e
             JOIN student_subjects ls ON ls.student_id = e.student_id
                                     AND ls.school_year = e.school_year AND ls.semester = e.semester
             JOIN section_subjects x ON x.id = ls.section_subject_id
             JOIN sections s ON s.id = x.section_id
            WHERE s.schedule_status <> 'approved')
$$;

-- (from 20261026010000_terms_foundation.sql)
CREATE OR REPLACE FUNCTION enforce_slip_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue an assessment slip';
  END IF;
  SELECT e.school_year, e.semester INTO NEW.school_year, NEW.semester FROM student_enrollment(NEW.student_id) e;
  IF NOT student_load_ready(NEW.student_id) THEN
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

-- (from 20261026010000_terms_foundation.sql)
CREATE OR REPLACE FUNCTION slip_ready_students()
RETURNS TABLE (
  student_id     uuid,
  student_number text,
  full_name      text,
  program_code   text,
  section        text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can see who is ready for an assessment slip';
  END IF;

  RETURN QUERY
  SELECT st.id,
         st.student_number::text,
         u.full_name::text,
         p.code::text,
         (p.code || ' ' || sec.year_level || sec.name)::text
    FROM students st
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    CROSS JOIN LATERAL student_enrollment(st.id) e
    JOIN sections sec ON sec.id = e.section_id
   WHERE student_load_ready(st.id)
     AND NOT EXISTS (SELECT 1 FROM assessment_slips sl
                      WHERE sl.student_id = st.id AND sl.school_year = e.school_year AND sl.semester = e.semester)
   ORDER BY st.student_number;
END;
$$;

-- (from 20261026010000_terms_foundation.sql) Everyone who takes the section subject is told, and a
-- COR issued to anyone who takes a subject of the section locks it.
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
         p.code || ' ' || s.year_level || s.name,
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
  IF EXISTS (SELECT 1 FROM cors c
               JOIN student_subjects ls ON ls.student_id = c.student_id
                                       AND ls.school_year = c.school_year AND ls.semester = c.semester
               JOIN section_subjects x ON x.id = ls.section_subject_id
              WHERE x.section_id = v_section) THEN
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
    FROM student_subjects ls
    JOIN students st ON st.id = ls.student_id
    JOIN applicants a ON a.id = st.applicant_id
   WHERE ls.section_subject_id = p_section_subject;
END;
$$;

-- (from 20261025000000_init.sql) A Professor's class list: the students who take one of their
-- section subjects, name and student number only.
CREATE OR REPLACE VIEW professor_class_lists AS
SELECT DISTINCT ss.section_id, sec.name AS section_name, sub.code AS subject_code, sub.title AS subject_title,
       st.student_number, u.full_name
FROM section_subjects ss
JOIN sections sec ON sec.id = ss.section_id
JOIN subjects sub ON sub.id = ss.subject_id
JOIN student_subjects ls ON ls.section_subject_id = ss.id
JOIN students st ON st.id = ls.student_id
JOIN applicants a ON a.id = st.applicant_id
JOIN users u ON u.id = a.user_id
WHERE ss.professor_id = current_actor_id();

-- ============================================================
-- 5. Grades read the list (from 20261026020000_grading.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION grade_sections() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_college uuid := app_college_id();
  v_result jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','dean','registrar','admin') THEN
    RAISE EXCEPTION 'You cannot read grades';
  END IF;

  SELECT coalesce(jsonb_agg(q.x ORDER BY q.x->>'label', q.x->>'code'), '[]'::jsonb) INTO v_result
    FROM (
      SELECT jsonb_build_object(
               'sectionId', sec.id,
               'subjectId', sub.id,
               'label', p.code || ' ' || sec.year_level || sec.name,
               'code', sub.code,
               'title', sub.title,
               'schoolYear', sec.school_year,
               'semester', sec.semester,
               'status', coalesce(gs.status, 'not_submitted'),
               'students', (SELECT count(DISTINCT ls.student_id) FROM student_subjects ls
                              JOIN section_subjects y ON y.id = ls.section_subject_id
                             WHERE y.section_id = sec.id AND y.subject_id = sub.id),
               'graded', (SELECT count(*) FROM grades g WHERE g.sheet_id = gs.id),
               'professor', (SELECT u.full_name FROM section_subjects x JOIN users u ON u.id = x.professor_id
                              WHERE x.section_id = sec.id AND x.subject_id = sub.id AND x.professor_id IS NOT NULL
                              ORDER BY x.meeting LIMIT 1)
             ) AS x
        FROM enrollment_term t
        JOIN sections sec ON sec.school_year = t.school_year AND sec.semester = t.semester
        JOIN programs p ON p.id = sec.program_id
        JOIN (SELECT DISTINCT section_id, subject_id FROM section_subjects) ssub ON ssub.section_id = sec.id
        JOIN subjects sub ON sub.id = ssub.subject_id
        LEFT JOIN grade_sheets gs ON gs.section_id = sec.id AND gs.subject_id = sub.id
       WHERE v_role IN ('registrar','admin')
          OR (v_role = 'dean' AND p.college_id = v_college)
          OR (v_role = 'professor' AND EXISTS (
                SELECT 1 FROM section_subjects x
                 WHERE x.section_id = sec.id AND x.subject_id = sub.id AND x.professor_id = v_actor))
    ) q;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION grade_sheet(p_section uuid, p_subject uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sheet grade_sheets%ROWTYPE;
  v_head record;
BEGIN
  IF NOT can_see_sheet(p_section, p_subject) THEN
    RAISE EXCEPTION 'You cannot read these grades';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject;
  SELECT p.code || ' ' || sec.year_level || sec.name AS label, sub.code, sub.title, sec.school_year, sec.semester
    INTO v_head
    FROM sections sec JOIN programs p ON p.id = sec.program_id, subjects sub
   WHERE sec.id = p_section AND sub.id = p_subject;
  IF v_head.label IS NULL THEN
    RAISE EXCEPTION 'That section subject was not found';
  END IF;

  RETURN jsonb_build_object(
    'sectionId', p_section,
    'subjectId', p_subject,
    'label', v_head.label,
    'code', v_head.code,
    'title', v_head.title,
    'schoolYear', v_head.school_year,
    'semester', v_head.semester,
    'status', coalesce(v_sheet.status, 'not_submitted'),
    'returnedReason', v_sheet.returned_reason,
    'students', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'studentId', st.id,
               'studentNumber', st.student_number,
               'fullName', u.full_name,
               'gradeId', g.id,
               'gradeText', g.grade_text,
               'outcome', g.outcome,
               'lapsed', coalesce(g.lapsed, false),
               'changePending', EXISTS (SELECT 1 FROM grade_changes c WHERE c.grade_id = g.id AND c.status IN ('pending_dean','pending_registrar'))
             ) ORDER BY st.student_number)
        FROM students st
        JOIN applicants a ON a.id = st.applicant_id
        JOIN users u ON u.id = a.user_id
        LEFT JOIN grades g ON g.sheet_id = v_sheet.id AND g.student_id = st.id
       WHERE in_section_subject(st.id, p_section, p_subject)), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION save_grades(p_section uuid, p_subject uuid, p_grades jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_sec sections%ROWTYPE;
  v_sheet grade_sheets%ROWTYPE;
  e jsonb;
  v_student uuid;
  v_text text;
  v_res record;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','admin') THEN
    RAISE EXCEPTION 'Only the Professor of this subject can enter grades';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM section_subjects x
        WHERE x.section_id = p_section AND x.subject_id = p_subject
          AND (v_role = 'admin' OR x.professor_id = v_actor)) THEN
    RAISE EXCEPTION 'Only the Professor of this subject can enter grades';
  END IF;
  IF NOT grading_scale_ready() THEN
    RAISE EXCEPTION 'The grading scale is not set. Ask Admin to set it in Content, Grading';
  END IF;
  IF jsonb_typeof(p_grades) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'The grades are missing';
  END IF;

  SELECT * INTO v_sec FROM sections WHERE id = p_section;
  PERFORM set_config('app.grade_write', 'on', true);
  INSERT INTO grade_sheets (section_id, subject_id, school_year, semester)
  VALUES (p_section, p_subject, v_sec.school_year, v_sec.semester)
  ON CONFLICT (section_id, subject_id) DO NOTHING;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;

  IF v_sheet.status = 'submitted' THEN
    RAISE EXCEPTION 'These grades are submitted. Ask the Dean to return them before editing';
  ELSIF v_sheet.status = 'approved' THEN
    RAISE EXCEPTION 'These grades are approved. Propose a grade change instead';
  END IF;

  FOR e IN SELECT value FROM jsonb_array_elements(p_grades) LOOP
    IF coalesce(e->>'studentId', '') !~ '^[0-9a-fA-F-]{36}$' THEN
      RAISE EXCEPTION 'A student is missing from the grades';
    END IF;
    v_student := (e->>'studentId')::uuid;
    IF NOT in_section_subject(v_student, p_section, p_subject) THEN
      RAISE EXCEPTION 'That student is not in this section';
    END IF;
    v_text := btrim(coalesce(e->>'grade', ''));
    IF v_text = '' THEN
      DELETE FROM grades WHERE sheet_id = v_sheet.id AND student_id = v_student;
      CONTINUE;
    END IF;
    SELECT * INTO v_res FROM resolve_grade(v_text);
    IF v_res.r_outcome IS NULL THEN
      RAISE EXCEPTION 'The grade "%" for student % is not on the grading scale',
        v_text, (SELECT student_number FROM students WHERE id = v_student);
    END IF;
    INSERT INTO grades (sheet_id, section_id, subject_id, student_id, school_year, semester, grade_text, outcome, entered_by)
    VALUES (v_sheet.id, p_section, p_subject, v_student, v_sheet.school_year, v_sheet.semester, v_res.r_text, v_res.r_outcome, v_actor)
    ON CONFLICT (sheet_id, student_id) DO UPDATE
       SET grade_text = EXCLUDED.grade_text, outcome = EXCLUDED.outcome,
           entered_by = EXCLUDED.entered_by, updated_at = now();
  END LOOP;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION submit_grades(p_section uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_sheet grade_sheets%ROWTYPE;
  v_missing text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','admin') THEN
    RAISE EXCEPTION 'Only the Professor of this subject can submit grades';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM section_subjects x
        WHERE x.section_id = p_section AND x.subject_id = p_subject
          AND (v_role = 'admin' OR x.professor_id = v_actor)) THEN
    RAISE EXCEPTION 'Only the Professor of this subject can submit grades';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;
  IF v_sheet.id IS NULL OR v_sheet.status <> 'draft' THEN
    RAISE EXCEPTION 'There are no draft grades to submit';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM student_subjects ls
                   JOIN section_subjects x ON x.id = ls.section_subject_id
                  WHERE x.section_id = p_section AND x.subject_id = p_subject) THEN
    RAISE EXCEPTION 'This section has no students';
  END IF;
  SELECT st.student_number INTO v_missing
    FROM students st
   WHERE in_section_subject(st.id, p_section, p_subject)
     AND NOT EXISTS (SELECT 1 FROM grades g WHERE g.sheet_id = v_sheet.id AND g.student_id = st.id)
   ORDER BY st.student_number LIMIT 1;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Enter a grade for student % before submitting', v_missing;
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_sheets
     SET status = 'submitted', submitted_by = v_actor, submitted_at = now(), returned_reason = NULL
   WHERE id = v_sheet.id;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

-- ============================================================
-- 6. Closing a term reads the list (from 20261026050000_close_term.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION term_missing_sheets() RETURNS TABLE (m_label text, m_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (p.code || ' ' || sec.year_level || sec.name)::text, sub.code::text
    FROM enrollment_term t
    JOIN sections sec ON sec.school_year = t.school_year AND sec.semester = t.semester
    JOIN programs p ON p.id = sec.program_id
    JOIN (SELECT DISTINCT section_id, subject_id FROM section_subjects) x ON x.section_id = sec.id
    JOIN subjects sub ON sub.id = x.subject_id
   WHERE EXISTS (SELECT 1 FROM student_subjects ls
                   JOIN section_subjects y ON y.id = ls.section_subject_id
                  WHERE y.section_id = sec.id AND y.subject_id = sub.id)
     AND NOT EXISTS (SELECT 1 FROM grade_sheets gs
                      WHERE gs.section_id = sec.id AND gs.subject_id = sub.id AND gs.status = 'approved')
   ORDER BY 1, 2
$$;

CREATE OR REPLACE FUNCTION close_term() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_term      enrollment_term%ROWTYPE;
  v_total     integer;
  v_names     text;
  r           record;
  v_counted   integer;
  v_reason    text;
  v_last_year integer;
  v_last_sem  text;
  v_result    text;
  v_promote   integer := 0;
  v_review    integer := 0;
  v_completed integer := 0;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can close a term';
  END IF;

  SELECT * INTO v_term FROM enrollment_term FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF EXISTS (SELECT 1 FROM term_closures c
              WHERE c.school_year = v_term.school_year AND c.semester = v_term.semester) THEN
    RAISE EXCEPTION 'This term is already closed';
  END IF;

  PERFORM lapse_incomplete_grades();

  SELECT count(*) INTO v_total FROM term_missing_sheets();
  IF v_total > 0 THEN
    SELECT string_agg(q.m_label || ' ' || q.m_code, ', ' ORDER BY q.m_label, q.m_code) INTO v_names
      FROM (SELECT m.m_label, m.m_code FROM term_missing_sheets() m ORDER BY m.m_label, m.m_code LIMIT 5) q;
    RAISE EXCEPTION 'Grades are not approved yet for: %',
      v_names || CASE WHEN v_total > 5 THEN ' and ' || (v_total - 5) || ' more' ELSE '' END;
  END IF;

  PERFORM set_config('app.term_write', 'on', true);
  INSERT INTO term_closures (school_year, semester, closed_by)
  VALUES (v_term.school_year, v_term.semester, current_actor_id());

  IF v_term.semester <> 'summer' THEN
    FOR r IN
      SELECT ss.student_id, ss.section_id, sec.program_id, sec.year_level, sec.name
        FROM student_sections ss
        JOIN sections sec ON sec.id = ss.section_id
        JOIN students st ON st.id = ss.student_id
        JOIN applicants a ON a.id = st.applicant_id
       WHERE ss.school_year = v_term.school_year AND ss.semester = v_term.semester
         AND a.withdrawn_at IS NULL
       ORDER BY st.student_number
    LOOP
      -- Every subject in the student's own list counts, whichever section it is taken in.
      SELECT count(*),
             string_agg(
               CASE coalesce(g.outcome, 'none')
                 WHEN 'incomplete' THEN 'Incomplete in ' || s.code
                 WHEN 'failed'     THEN 'Failed ' || s.code
                 WHEN 'dropped'    THEN 'Dropped ' || s.code
                 ELSE 'No grade in ' || s.code
               END, '; ' ORDER BY s.code)
             FILTER (WHERE coalesce(g.outcome, 'none') <> 'passed')
        INTO v_counted, v_reason
        FROM (SELECT DISTINCT y.section_id, y.subject_id
                FROM student_subjects ls
                JOIN section_subjects y ON y.id = ls.section_subject_id
               WHERE ls.student_id = r.student_id
                 AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester) d
        JOIN subjects s ON s.id = d.subject_id
        LEFT JOIN grades g ON g.student_id = r.student_id AND g.section_id = d.section_id AND g.subject_id = s.id
                          AND EXISTS (SELECT 1 FROM grade_sheets gs WHERE gs.id = g.sheet_id AND gs.status = 'approved');

      SELECT max(sub.year_level) INTO v_last_year FROM subjects sub WHERE sub.program_id = r.program_id;
      v_last_sem := CASE WHEN EXISTS (SELECT 1 FROM subjects sub
                                       WHERE sub.program_id = r.program_id AND sub.year_level = v_last_year
                                         AND sub.semester = '2nd')
                         THEN '2nd' ELSE '1st' END;

      IF v_counted = 0 THEN
        v_result := 'review';
        v_reason := 'The student has no subjects this term';
      ELSIF v_reason IS NOT NULL THEN
        v_result := 'review';
      ELSIF v_last_year IS NOT NULL AND r.year_level >= v_last_year AND v_term.semester = v_last_sem THEN
        v_result := 'completed';
        v_reason := NULL;
      ELSE
        v_result := 'promote';
        v_reason := NULL;
      END IF;

      INSERT INTO term_results (school_year, semester, student_id, program_id, year_level, section_name, result, reason)
      VALUES (v_term.school_year, v_term.semester, r.student_id, r.program_id, r.year_level, r.name, v_result, v_reason);

      IF v_result = 'promote' THEN
        v_promote := v_promote + 1;
      ELSIF v_result = 'review' THEN
        v_review := v_review + 1;
      ELSE
        v_completed := v_completed + 1;
      END IF;
    END LOOP;
  END IF;
  PERFORM set_config('app.term_write', 'off', true);

  RETURN jsonb_build_object('promote', v_promote, 'review', v_review, 'completed', v_completed);
END;
$$;

-- ============================================================
-- 7. The load builder
-- ============================================================
-- One student's load for the current term, and every subject of the program by where the student
-- stands on it: in_load, passed, blocked (with the prerequisite named), not_offered or allowed (with
-- the sections of this term that offer it). Staff of the student's college and Admin only.
CREATE OR REPLACE FUNCTION student_load(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role     text := app_role();
  v_term     enrollment_term%ROWTYPE;
  v_program  uuid;
  v_number   text;
  v_name     text;
  v_code     text;
  v_section  uuid;
  v_label    text;
  v_locked   boolean;
  v_places   jsonb;
  v_subjects jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read a student''s load';
  END IF;
  SELECT a.program_id, st.student_number, u.full_name, p.code
    INTO v_program, v_number, v_name, v_code
    FROM students st
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
   WHERE st.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;

  SELECT ss.section_id, pr.code || ' ' || sec.year_level || sec.name
    INTO v_section, v_label
    FROM student_sections ss
    JOIN sections sec ON sec.id = ss.section_id
    JOIN programs pr ON pr.id = sec.program_id
   WHERE ss.student_id = p_student AND ss.school_year = v_term.school_year AND ss.semester = v_term.semester;

  v_locked := EXISTS (SELECT 1 FROM assessment_slips sl
                       WHERE sl.student_id = p_student AND sl.school_year = v_term.school_year AND sl.semester = v_term.semester);

  -- The sections a student without a section can be placed in.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'sectionId', sec.id,
           'label', pr.code || ' ' || sec.year_level || sec.name,
           'taken', (SELECT count(*) FROM student_sections x WHERE x.section_id = sec.id),
           'capacity', sec.capacity) ORDER BY sec.year_level, sec.name), '[]'::jsonb)
    INTO v_places
    FROM sections sec JOIN programs pr ON pr.id = sec.program_id
   WHERE sec.program_id = v_program AND sec.school_year = v_term.school_year AND sec.semester = v_term.semester;

  SELECT coalesce(jsonb_agg(q.item ORDER BY q.yl, q.sr, q.code), '[]'::jsonb) INTO v_subjects
    FROM (
      SELECT sub.year_level AS yl, semester_rank(sub.semester) AS sr, sub.code AS code,
             jsonb_build_object(
               'subjectId', sub.id,
               'code', sub.code,
               'title', sub.title,
               'yearLevel', sub.year_level,
               'semester', sub.semester,
               'status', CASE
                           WHEN cur.label IS NOT NULL THEN 'in_load'
                           WHEN student_has_passed(p_student, sub.id) THEN 'passed'
                           WHEN NOT subject_in_term(sub.semester, sub.offered_in_summer, v_term.semester) OR opt.n = 0 THEN 'not_offered'
                           WHEN blk.n > 0 THEN 'blocked'
                           ELSE 'allowed' END,
               'source', cur.source,
               'takenIn', cur.label,
               'blockedBy', blk.j,
               'options', opt.j) AS item
        FROM subjects sub
        LEFT JOIN LATERAL (
          SELECT pr.code || ' ' || sec.year_level || sec.name AS label, ls.source
            FROM student_subjects ls
            JOIN section_subjects x ON x.id = ls.section_subject_id
            JOIN sections sec ON sec.id = x.section_id
            JOIN programs pr ON pr.id = sec.program_id
           WHERE ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
             AND x.subject_id = sub.id
           LIMIT 1) cur ON true
        LEFT JOIN LATERAL (
          SELECT coalesce(jsonb_agg(jsonb_build_object('code', b.b_code, 'status', b.b_status) ORDER BY b.b_code), '[]'::jsonb) AS j,
                 count(*) AS n
            FROM student_blocking_prerequisites(p_student, sub.id) b) blk ON true
        LEFT JOIN LATERAL (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
                          'sectionId', o.id, 'label', o.label, 'taken', o.taken, 'capacity', o.capacity) ORDER BY o.label), '[]'::jsonb) AS j,
                 count(*) AS n
            FROM (
              SELECT sec.id, pr.code || ' ' || sec.year_level || sec.name AS label, sec.capacity,
                     (SELECT count(DISTINCT l2.student_id) FROM student_subjects l2
                        JOIN section_subjects y ON y.id = l2.section_subject_id
                       WHERE y.section_id = sec.id AND y.subject_id = sub.id) AS taken
                FROM sections sec JOIN programs pr ON pr.id = sec.program_id
               WHERE sec.program_id = v_program AND sec.school_year = v_term.school_year AND sec.semester = v_term.semester
                 AND EXISTS (SELECT 1 FROM section_subjects y WHERE y.section_id = sec.id AND y.subject_id = sub.id)
            ) o) opt ON true
       WHERE sub.program_id = v_program AND sub.year_level IS NOT NULL
    ) q;

  RETURN jsonb_build_object(
    'studentId', p_student,
    'studentNumber', v_number,
    'fullName', v_name,
    'programCode', v_code,
    'schoolYear', v_term.school_year,
    'semester', v_term.semester,
    'enrolled', v_section IS NOT NULL,
    'section', v_label,
    'locked', v_locked,
    'places', v_places,
    'subjects', v_subjects);
END;
$$;

CREATE OR REPLACE FUNCTION add_subject_to_load(p_student uuid, p_section uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_term    enrollment_term%ROWTYPE;
  v_program uuid;
  v_user    uuid;
  v_sec     sections%ROWTYPE;
  v_sub     subjects%ROWTYPE;
  v_block   text;
  v_taken   integer;
  v_clash   text;
  v_label   text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary or the Dean can change a student''s load';
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
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'This student belongs to another college';
  END IF;

  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  -- Two people changing the same student's load queue on the enrollment row.
  PERFORM 1 FROM student_sections
   WHERE student_id = p_student AND school_year = v_term.school_year AND semester = v_term.semester
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Place the student in a section of the current term first';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips
              WHERE student_id = p_student AND school_year = v_term.school_year AND semester = v_term.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the load can no longer be changed';
  END IF;

  SELECT * INTO v_sec FROM sections WHERE id = p_section FOR UPDATE;
  IF v_sec.id IS NULL THEN
    RAISE EXCEPTION 'Section not found';
  END IF;
  IF v_sec.program_id <> v_program THEN
    RAISE EXCEPTION 'A subject can only be taken from a section of the student''s own program';
  END IF;
  IF (v_sec.school_year, v_sec.semester) IS DISTINCT FROM (v_term.school_year, v_term.semester) THEN
    RAISE EXCEPTION 'Only a section of the current term can be used';
  END IF;

  SELECT * INTO v_sub FROM subjects WHERE id = p_subject;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'Subject not found';
  END IF;
  IF v_sub.program_id <> v_program THEN
    RAISE EXCEPTION '% is not a subject of the student''s program', v_sub.code;
  END IF;
  IF NOT subject_in_term(v_sub.semester, v_sub.offered_in_summer, v_term.semester) THEN
    RAISE EXCEPTION '% is not offered in the % semester', v_sub.code, v_term.semester;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM section_subjects x WHERE x.section_id = p_section AND x.subject_id = p_subject) THEN
    RAISE EXCEPTION 'That section does not offer %', v_sub.code;
  END IF;
  IF EXISTS (SELECT 1 FROM student_subjects ls
               JOIN section_subjects x ON x.id = ls.section_subject_id
              WHERE ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
                AND x.subject_id = p_subject) THEN
    RAISE EXCEPTION 'The student already takes %', v_sub.code;
  END IF;
  IF student_has_passed(p_student, p_subject) THEN
    RAISE EXCEPTION 'The student already passed or was credited %', v_sub.code;
  END IF;

  -- The one definition of eligibility (step 20). No role can add past it.
  SELECT string_agg(b.b_code || ' (' || replace(b.b_status, '_', ' ') || ')', ', ' ORDER BY b.b_code) INTO v_block
    FROM student_blocking_prerequisites(p_student, p_subject) b;
  IF v_block IS NOT NULL THEN
    RAISE EXCEPTION '% needs a passed prerequisite: %', v_sub.code, v_block;
  END IF;

  SELECT pr.code || ' ' || v_sec.year_level || v_sec.name INTO v_label FROM programs pr WHERE pr.id = v_sec.program_id;
  SELECT count(DISTINCT l2.student_id)::integer INTO v_taken
    FROM student_subjects l2 JOIN section_subjects y ON y.id = l2.section_subject_id
   WHERE y.section_id = p_section AND y.subject_id = p_subject;
  IF v_taken >= v_sec.capacity THEN
    RAISE EXCEPTION '% has no free seat for % (% of %)', v_label, v_sub.code, v_taken, v_sec.capacity;
  END IF;

  -- A time that overlaps another subject already in the load.
  SELECT cs.code INTO v_clash
    FROM student_subjects ls
    JOIN section_subjects a1 ON a1.id = ls.section_subject_id
    JOIN subjects cs ON cs.id = a1.subject_id
    JOIN section_subjects n ON n.section_id = p_section AND n.subject_id = p_subject
   WHERE ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
     AND a1.day_of_week IS NOT NULL AND n.day_of_week = a1.day_of_week
     AND a1.start_time IS NOT NULL AND n.start_time IS NOT NULL
     AND a1.start_time < n.end_time AND n.start_time < a1.end_time
   LIMIT 1;
  IF v_clash IS NOT NULL THEN
    RAISE EXCEPTION '% clashes in time with % already in the load', v_sub.code, v_clash;
  END IF;

  PERFORM set_config('app.load_write', 'on', true);
  INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source, added_by)
  SELECT p_student, v_term.school_year, v_term.semester, x.id, 'added', current_actor_id()
    FROM section_subjects x
   WHERE x.section_id = p_section AND x.subject_id = p_subject;
  PERFORM set_config('app.load_write', 'off', true);

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'load_changed', 'Your subjects changed',
          v_sub.code || ' in ' || v_label || ' was added to your subjects. Your college is preparing your schedule.');
END;
$$;

CREATE OR REPLACE FUNCTION remove_subject_from_load(p_student uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_term    enrollment_term%ROWTYPE;
  v_user    uuid;
  v_code    text;
  v_rows    integer;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary or the Dean can change a student''s load';
  END IF;
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'This student belongs to another college';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips
              WHERE student_id = p_student AND school_year = v_term.school_year AND semester = v_term.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the load can no longer be changed';
  END IF;

  SELECT code INTO v_code FROM subjects WHERE id = p_subject;
  DELETE FROM student_subjects ls
   USING section_subjects x
   WHERE x.id = ls.section_subject_id AND x.subject_id = p_subject
     AND ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
     AND ls.source = 'added';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'That subject was not added by staff, so it stays in the load';
  END IF;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'load_changed', 'Your subjects changed',
          v_code || ' was removed from your subjects. Your college is preparing your schedule.');
END;
$$;

-- ============================================================
-- 8. Who may call what
--    The helpers stay internal.
-- ============================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'in_section_subject(uuid, uuid, uuid)', 'copy_section_load(uuid, uuid)', 'student_load_ready(uuid)',
    'student_load(uuid)', 'add_subject_to_load(uuid, uuid, uuid)', 'remove_subject_from_load(uuid, uuid)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', f);
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    FOREACH f IN ARRAY ARRAY[
      'in_section_subject(uuid, uuid, uuid)', 'copy_section_load(uuid, uuid)', 'student_load_ready(uuid)'
    ] LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', f);
    END LOOP;

    FOREACH f IN ARRAY ARRAY[
      'student_load(uuid)', 'add_subject_to_load(uuid, uuid, uuid)', 'remove_subject_from_load(uuid, uuid)'
    ] LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END LOOP;
  END IF;
END $$;
