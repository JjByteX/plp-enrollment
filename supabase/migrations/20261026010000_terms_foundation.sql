-- ============================================================
-- supabase/migrations/20261026010000_terms_foundation.sql
-- Step 18: terms foundation (docs/step-18-returning-students-plan.md).
--
-- Forward-only. Makes a second term possible and changes nothing a current
-- student sees. No new screen.
--
--   - subjects.semester ('1st','2nd','summer') and subjects.offered_in_summer.
--     A section takes the subjects of its year level that are offered in its
--     semester.
--   - sections.school_year and sections.semester. A section belongs to one term
--     for good. A new section takes the current term (enrollment_term). Section
--     uniqueness now includes the term.
--   - student_sections is the enrollment table: one row per student per term
--     (primary key student_id, school_year, semester). It keeps its name so the
--     policies, the audit trigger and the class list view keep working; the
--     term is copied from the section by a trigger.
--   - assessment_slips, payments and cors are one per student per term.
--   - A student's "current enrollment" is the one in the current term, or else
--     the latest one (student_enrollment). Everything that used to read the one
--     student_sections row reads that.
--   - Placement still seats only students with no enrollment at all, in Year 1
--     of the current term (decision #19). Promotion is step 21.
--
-- Replaced functions, each written from the latest version of that function
-- with the term added: student_schedule_json, my_section_id, enforce_section_gates,
-- after_section_created, add_subject_to_draft_sections, place_student_in_section,
-- move_student_section, enforce_slip_gate, issue_assessment_slip,
-- issue_all_ready_slips, assessment_slip, open_payment_after_slip, record_payment,
-- payment_queue, my_payment_status, enforce_cor_gate, issue_cor,
-- issue_all_ready_cors, certificate_of_registration, amend_schedule,
-- my_schedule_changed, withdraw_enrollment_core, withdraw_my_enrollment,
-- admissions_status_due.
--
-- Deliberate behaviour changes:
--   - A section can only be created once Admin has set the term.
--   - A COR carries the term of the enrollment it belongs to, not whatever the
--     current term is on the day it is issued. They are the same unless Admin
--     changes the term between a student's slip and COR.
--
-- Existing rows are backfilled into the current term. A section with students
-- who already have a COR takes the term of the latest of those CORs. If sections,
-- slips or payments exist and no term is set, this migration stops and nothing
-- is applied: insert the term (INSERT INTO enrollment_term ...) and run it again.
-- ============================================================

-- ============================================================
-- 1. Small helpers
-- ============================================================
CREATE OR REPLACE FUNCTION semester_rank(p_semester text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester WHEN '1st' THEN 1 WHEN '2nd' THEN 2 WHEN 'summer' THEN 3 END
$$;

-- Is a subject taken in a term? Its own semester, or summer when it is flagged for summer.
CREATE OR REPLACE FUNCTION subject_in_term(p_subject_semester text, p_offered_in_summer boolean, p_term_semester text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_subject_semester = p_term_semester OR (p_term_semester = 'summer' AND coalesce(p_offered_in_summer, false))
$$;

-- ============================================================
-- 2. Subjects: semester and the summer flag
-- ============================================================
ALTER TABLE subjects ADD COLUMN semester text NULL CHECK (semester IN ('1st','2nd','summer'));
ALTER TABLE subjects ADD COLUMN offered_in_summer boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN subjects.semester IS 'The term a regular student takes the subject: 1st, 2nd or summer.';
COMMENT ON COLUMN subjects.offered_in_summer IS 'The subject also runs in summer terms (retakes). Not set for a summer-only subject.';

-- Existing subjects were loaded for the current term's semester (the old
-- "one semester per year level" workaround).
UPDATE subjects SET semester = coalesce((SELECT semester FROM enrollment_term), '1st');
ALTER TABLE subjects ALTER COLUMN semester SET NOT NULL;
ALTER TABLE subjects ADD CONSTRAINT subjects_summer_flag CHECK (NOT (semester = 'summer' AND offered_in_summer));

-- A subject added without a semester takes the current term's semester, so the
-- seeders and any older caller keep working.
CREATE OR REPLACE FUNCTION set_subject_semester() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.semester IS NULL THEN
    SELECT t.semester INTO NEW.semester FROM enrollment_term t;
    NEW.semester := coalesce(NEW.semester, '1st');
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_subjects_semester BEFORE INSERT ON subjects
    FOR EACH ROW EXECUTE FUNCTION set_subject_semester();

-- ============================================================
-- 3. Sections: the term, backfilled, then required
-- ============================================================
ALTER TABLE sections ADD COLUMN school_year text NULL;
ALTER TABLE sections ADD COLUMN semester text NULL;

DO $$
DECLARE
  v_term    enrollment_term%ROWTYPE;
  v_missing integer;
BEGIN
  SELECT * INTO v_term FROM enrollment_term;

  -- a section with students who have a COR takes the term of the latest of those CORs
  UPDATE sections s
     SET school_year = t.school_year, semester = t.semester
    FROM (
      SELECT DISTINCT ON (ss.section_id) ss.section_id, c.school_year, c.semester
        FROM student_sections ss
        JOIN cors c ON c.student_id = ss.student_id
       ORDER BY ss.section_id, c.issued_at DESC
    ) t
   WHERE t.section_id = s.id;

  IF v_term.id IS NOT NULL THEN
    UPDATE sections SET school_year = v_term.school_year, semester = v_term.semester WHERE school_year IS NULL;
  END IF;

  SELECT count(*) INTO v_missing FROM sections WHERE school_year IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'The school year and semester are not set and % sections exist. Insert the term first (INSERT INTO enrollment_term (school_year, semester) VALUES (''2026-2027'', ''1st'')) and run this migration again', v_missing;
  END IF;
END $$;

ALTER TABLE sections ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE sections ALTER COLUMN semester SET NOT NULL;
ALTER TABLE sections ADD CONSTRAINT sections_school_year_format CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$');
ALTER TABLE sections ADD CONSTRAINT sections_semester_valid CHECK (semester IN ('1st','2nd','summer'));
CREATE INDEX idx_sections_term ON sections (school_year, semester);

-- Replace the old uniqueness constraints, whatever the database named them.
DO $$
DECLARE
  r record;
  c text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('sections', ARRAY['name','program_id','year_level']),
      ('assessment_slips', ARRAY['student_id']),
      ('payments', ARRAY['student_id']),
      ('cors', ARRAY['student_id'])
    ) v(tbl, cols)
  LOOP
    SELECT con.conname INTO c
      FROM pg_constraint con
     WHERE con.conrelid = r.tbl::regclass
       AND con.contype = 'u'
       AND (SELECT array_agg(att.attname::text ORDER BY att.attname)
              FROM unnest(con.conkey) k
              JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k)
           = r.cols;
    IF c IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', r.tbl, c);
    END IF;
  END LOOP;
END $$;

ALTER TABLE sections
    ADD CONSTRAINT sections_term_name_key UNIQUE (program_id, year_level, name, school_year, semester);

-- A new section takes the current term. The Secretary cannot read the term row,
-- so this runs with the owner's rights. A section created without a name takes
-- the next letter for its program, year level and term: A, then B, C, D.
-- (A name given on purpose, such as by a seeder, is kept.)
CREATE OR REPLACE FUNCTION set_section_term() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_last text;
BEGIN
  IF NEW.school_year IS NULL OR NEW.semester IS NULL THEN
    SELECT t.school_year, t.semester INTO NEW.school_year, NEW.semester FROM enrollment_term t;
    IF NEW.school_year IS NULL THEN
      RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them before creating a section';
    END IF;
  END IF;

  IF NEW.name IS NULL OR btrim(NEW.name) = '' THEN
    PERFORM pg_advisory_xact_lock(hashtext(NEW.program_id::text || '/' || NEW.year_level || '/' || NEW.school_year || '/' || NEW.semester));
    SELECT max(s.name) INTO v_last FROM sections s
     WHERE s.program_id = NEW.program_id AND s.year_level = NEW.year_level
       AND s.school_year = NEW.school_year AND s.semester = NEW.semester
       AND s.name ~ '^[A-Z]$';
    IF v_last = 'Z' THEN
      RAISE EXCEPTION 'This year level already has sections A to Z';
    END IF;
    NEW.name := CASE WHEN v_last IS NULL THEN 'A' ELSE chr(ascii(v_last) + 1) END;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_sections_term BEFORE INSERT ON sections
    FOR EACH ROW EXECUTE FUNCTION set_section_term();

-- ============================================================
-- 4. Enrollments (student_sections): one per student per term
-- ============================================================
ALTER TABLE student_sections ADD COLUMN school_year text NULL;
ALTER TABLE student_sections ADD COLUMN semester text NULL;

UPDATE student_sections ss
   SET school_year = sec.school_year, semester = sec.semester
  FROM sections sec
 WHERE sec.id = ss.section_id;

ALTER TABLE student_sections ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE student_sections ALTER COLUMN semester SET NOT NULL;
ALTER TABLE student_sections DROP CONSTRAINT student_sections_pkey;
ALTER TABLE student_sections ADD PRIMARY KEY (student_id, school_year, semester);
COMMENT ON TABLE student_sections IS 'The enrollment: one row per student per term, holding the section. The term is copied from the section.';

-- The term always comes from the section. A row never moves to a section of another term.
CREATE OR REPLACE FUNCTION set_enrollment_term() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_year text;
  v_sem  text;
BEGIN
  SELECT sec.school_year, sec.semester INTO v_year, v_sem FROM sections sec WHERE sec.id = NEW.section_id;
  IF TG_OP = 'UPDATE' AND (v_year, v_sem) IS DISTINCT FROM (OLD.school_year, OLD.semester) THEN
    RAISE EXCEPTION 'A student cannot be moved to a section of another term';
  END IF;
  NEW.school_year := v_year;
  NEW.semester := v_sem;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_student_sections_term BEFORE INSERT OR UPDATE OF section_id ON student_sections
    FOR EACH ROW EXECUTE FUNCTION set_enrollment_term();

-- ============================================================
-- 5. Slips, payments and CORs: one per student per term
-- ============================================================
ALTER TABLE assessment_slips ADD COLUMN school_year text NULL;
ALTER TABLE assessment_slips ADD COLUMN semester text NULL;
ALTER TABLE payments ADD COLUMN school_year text NULL;
ALTER TABLE payments ADD COLUMN semester text NULL;

-- The student's enrollment term, else the term of their COR, else the current term.
UPDATE assessment_slips sl
   SET school_year = x.school_year, semester = x.semester
  FROM (
    SELECT d.id,
           coalesce(ss.school_year, c.school_year, t.school_year) AS school_year,
           coalesce(ss.semester, c.semester, t.semester) AS semester
      FROM assessment_slips d
      LEFT JOIN student_sections ss ON ss.student_id = d.student_id
      LEFT JOIN cors c ON c.student_id = d.student_id
      LEFT JOIN enrollment_term t ON true
  ) x
 WHERE x.id = sl.id;

UPDATE payments p
   SET school_year = x.school_year, semester = x.semester
  FROM (
    SELECT d.id,
           coalesce(ss.school_year, c.school_year, t.school_year) AS school_year,
           coalesce(ss.semester, c.semester, t.semester) AS semester
      FROM payments d
      LEFT JOIN student_sections ss ON ss.student_id = d.student_id
      LEFT JOIN cors c ON c.student_id = d.student_id
      LEFT JOIN enrollment_term t ON true
  ) x
 WHERE x.id = p.id;

DO $$
DECLARE
  v_missing integer;
  v_mismatch integer;
BEGIN
  SELECT (SELECT count(*) FROM assessment_slips WHERE school_year IS NULL)
       + (SELECT count(*) FROM payments WHERE school_year IS NULL)
    INTO v_missing;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'The school year and semester are not set and % slips or payments exist. Insert the term first and run this migration again', v_missing;
  END IF;

  -- A COR issued under an older term than its section carries that older term and
  -- is not found by the term-matched reads. Only possible if Admin changed the
  -- term after a COR was issued.
  SELECT count(*) INTO v_mismatch
    FROM cors c
    JOIN student_sections ss ON ss.student_id = c.student_id
   WHERE (ss.school_year, ss.semester) IS DISTINCT FROM (c.school_year, c.semester);
  IF v_mismatch > 0 THEN
    RAISE NOTICE '% CORs carry a different term than the student''s enrollment. Check them in the audit log.', v_mismatch;
  END IF;
END $$;

ALTER TABLE assessment_slips ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE assessment_slips ALTER COLUMN semester SET NOT NULL;
ALTER TABLE payments ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE payments ALTER COLUMN semester SET NOT NULL;
ALTER TABLE assessment_slips ADD CONSTRAINT assessment_slips_school_year_format CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$');
ALTER TABLE assessment_slips ADD CONSTRAINT assessment_slips_semester_valid CHECK (semester IN ('1st','2nd','summer'));
ALTER TABLE payments ADD CONSTRAINT payments_school_year_format CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$');
ALTER TABLE payments ADD CONSTRAINT payments_semester_valid CHECK (semester IN ('1st','2nd','summer'));

ALTER TABLE assessment_slips ADD CONSTRAINT assessment_slips_student_term_key UNIQUE (student_id, school_year, semester);
ALTER TABLE payments ADD CONSTRAINT payments_student_term_key UNIQUE (student_id, school_year, semester);
ALTER TABLE cors ADD CONSTRAINT cors_student_term_key UNIQUE (student_id, school_year, semester);

-- ============================================================
-- 6. A student's current enrollment, and the current term
--    The enrollment in the current term, else the latest one. Internal.
-- ============================================================
CREATE OR REPLACE FUNCTION student_enrollment(p_student uuid) RETURNS SETOF student_sections
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT ss.*
    FROM student_sections ss
   WHERE ss.student_id = p_student
   ORDER BY EXISTS (SELECT 1 FROM enrollment_term t
                     WHERE t.school_year = ss.school_year AND t.semester = ss.semester) DESC,
            ss.school_year DESC,
            semester_rank(ss.semester) DESC
   LIMIT 1
$$;

-- The current term for the schedule pages (the Secretary cannot read the term row).
CREATE OR REPLACE FUNCTION current_term() RETURNS TABLE (school_year text, semester text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.school_year, t.semester FROM enrollment_term t
$$;

-- A payment takes the term of the student's enrollment; a student with no
-- enrollment takes the current term.
CREATE OR REPLACE FUNCTION set_payment_term() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.school_year IS NULL OR NEW.semester IS NULL THEN
    SELECT e.school_year, e.semester INTO NEW.school_year, NEW.semester FROM student_enrollment(NEW.student_id) e;
    IF NEW.school_year IS NULL THEN
      SELECT t.school_year, t.semester INTO NEW.school_year, NEW.semester FROM enrollment_term t;
    END IF;
    IF NEW.school_year IS NULL THEN
      RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payments_term BEFORE INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION set_payment_term();

-- ============================================================
-- 7. Sections: the term never changes (from 20261025070000_section_scheduling.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_section_gates() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_actor   uuid := current_actor_id();
  v_college uuid;
  v_reason  text := nullif(trim(coalesce(current_setting('app.audit_reason', true), '')), '');
  v_rows    integer;
  v_open    integer;
BEGIN
  IF NEW.program_id IS DISTINCT FROM OLD.program_id OR NEW.year_level IS DISTINCT FROM OLD.year_level THEN
    RAISE EXCEPTION 'The program and year level of a section cannot be changed';
  END IF;
  IF NEW.school_year IS DISTINCT FROM OLD.school_year OR NEW.semester IS DISTINCT FROM OLD.semester THEN
    RAISE EXCEPTION 'The term of a section cannot be changed';
  END IF;

  IF NEW.schedule_status = OLD.schedule_status THEN
    -- the sign-off and rejection columns are only ever set by a status change
    NEW.prepared_by := OLD.prepared_by;
    NEW.dean_signed_by := OLD.dean_signed_by;
    NEW.dean_signed_at := OLD.dean_signed_at;
    NEW.approved_by := OLD.approved_by;
    NEW.approved_at := OLD.approved_at;
    NEW.rejected_reason := OLD.rejected_reason;
    NEW.rejected_by := OLD.rejected_by;
    NEW.rejected_at := OLD.rejected_at;
    IF v_role = 'registrar' AND (NEW.name, NEW.capacity) IS DISTINCT FROM (OLD.name, OLD.capacity) THEN
      RAISE EXCEPTION 'The Registrar cannot edit section details';
    END IF;
    RETURN NEW;
  END IF;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'An identified user is required to change a schedule status';
  END IF;
  SELECT college_id INTO v_college FROM programs WHERE id = NEW.program_id;

  IF OLD.schedule_status = 'draft' AND NEW.schedule_status = 'pending_dean' THEN
    IF v_role NOT IN ('college_secretary','dean','admin')
       OR (v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college) THEN
      RAISE EXCEPTION 'Only this college''s Secretary or Dean can submit a schedule for sign-off';
    END IF;
    SELECT count(*)::integer,
           count(*) FILTER (WHERE professor_id IS NULL OR room_id IS NULL OR day_of_week IS NULL)::integer
      INTO v_rows, v_open
      FROM section_subjects WHERE section_id = NEW.id;
    IF v_rows = 0 THEN
      RAISE EXCEPTION 'This section has no subjects yet, so there is nothing to sign off';
    END IF;
    IF v_open > 0 THEN
      RAISE EXCEPTION '% of % subjects still need a professor, room and time', v_open, v_rows;
    END IF;
    NEW.prepared_by := v_actor;
    NEW.rejected_reason := NULL;
    NEW.rejected_by := NULL;
    NEW.rejected_at := NULL;
  ELSIF OLD.schedule_status = 'pending_dean' AND NEW.schedule_status = 'dean_signed' THEN
    IF v_role NOT IN ('dean','admin')
       OR (v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college) THEN
      RAISE EXCEPTION 'Only this college''s Dean can sign off professor loading';
    END IF;
    NEW.dean_signed_by := v_actor;
    NEW.dean_signed_at := now();
  ELSIF OLD.schedule_status = 'dean_signed' AND NEW.schedule_status = 'approved' THEN
    IF v_role NOT IN ('registrar','admin') THEN
      RAISE EXCEPTION 'Only the Registrar can approve a schedule';
    END IF;
    NEW.approved_by := v_actor;
    NEW.approved_at := now();
  ELSIF OLD.schedule_status = 'pending_dean' AND NEW.schedule_status = 'draft' THEN
    IF v_role NOT IN ('dean','admin')
       OR (v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college) THEN
      RAISE EXCEPTION 'Only this college''s Dean can reject a schedule waiting for sign-off';
    END IF;
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'A reason is required to reject a schedule';
    END IF;
    NEW.rejected_reason := v_reason;
    NEW.rejected_by := v_actor;
    NEW.rejected_at := now();
  ELSIF OLD.schedule_status = 'dean_signed' AND NEW.schedule_status = 'draft' THEN
    IF v_role NOT IN ('registrar','admin') THEN
      RAISE EXCEPTION 'Only the Registrar can reject a schedule signed by the Dean';
    END IF;
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'A reason is required to reject a schedule';
    END IF;
    NEW.rejected_reason := v_reason;
    NEW.rejected_by := v_actor;
    NEW.rejected_at := now();
    -- the Dean signs again after the Secretary fixes it
    NEW.dean_signed_by := NULL;
    NEW.dean_signed_at := NULL;
  ELSE
    RAISE EXCEPTION 'Invalid schedule status change: % to %', OLD.schedule_status, NEW.schedule_status;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 8. Subjects fill a section by year level and semester
--    (from 20261025090000_laboratory_meetings.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION after_section_created() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO section_subjects (section_id, subject_id, meeting)
  SELECT NEW.id, sub.id, m.meeting
    FROM subjects sub
    CROSS JOIN (VALUES ('lecture'), ('laboratory')) m(meeting)
   WHERE sub.program_id = NEW.program_id AND sub.year_level = NEW.year_level
     AND subject_in_term(sub.semester, sub.offered_in_summer, NEW.semester)
     AND (m.meeting = 'lecture' OR sub.has_laboratory)
   ON CONFLICT (section_id, subject_id, meeting) DO NOTHING;
  PERFORM place_waiting_students(NEW.program_id);
  RETURN NULL;
END;
$$;

-- A subject added to the catalog, or flagged as having a laboratory later,
-- reaches the draft sections of its year level in the current term only.
CREATE OR REPLACE FUNCTION add_subject_to_draft_sections() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.year_level IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO section_subjects (section_id, subject_id, meeting)
  SELECT sec.id, NEW.id, m.meeting
    FROM sections sec
    JOIN enrollment_term t ON t.school_year = sec.school_year AND t.semester = sec.semester
    CROSS JOIN (VALUES ('lecture'), ('laboratory')) m(meeting)
   WHERE sec.program_id = NEW.program_id AND sec.year_level = NEW.year_level AND sec.schedule_status = 'draft'
     AND subject_in_term(NEW.semester, NEW.offered_in_summer, sec.semester)
     AND (m.meeting = 'lecture' OR NEW.has_laboratory)
   ON CONFLICT (section_id, subject_id, meeting) DO NOTHING;
  RETURN NULL;
END;
$$;

-- ============================================================
-- 9. The schedule builder and the student's section
--    (from 20261025180000_schedule_changes.sql and the init migration)
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
    FROM student_enrollment(p_student) sts
    JOIN section_subjects ss ON ss.section_id = sts.section_id
    JOIN subjects sub ON sub.id = ss.subject_id
    LEFT JOIN users pr ON pr.id = ss.professor_id
    LEFT JOIN rooms r ON r.id = ss.room_id
$$;

CREATE OR REPLACE FUNCTION my_section_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT e.section_id FROM student_enrollment(my_student_id()) e
$$;

-- ============================================================
-- 10. Placement, still new students only, Year 1 of the current term
--     (from 20261025190000_withdrawals.sql)
-- ============================================================
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
      FROM sections sec
      JOIN programs p ON p.id = sec.program_id
      JOIN enrollment_term t ON t.school_year = sec.school_year AND t.semester = sec.semester
     WHERE sec.program_id = v_program AND sec.year_level = 1
     ORDER BY sec.name, sec.id
       FOR UPDATE OF sec
  LOOP
    IF (SELECT count(*) FROM student_sections WHERE section_id = v_sec.id) < v_sec.capacity THEN
      INSERT INTO student_sections (student_id, section_id) VALUES (p_student, v_sec.id);
      INSERT INTO notifications (user_id, kind, title, message)
      VALUES (v_user, 'section_placed', 'Your section',
              'You are placed in ' || v_sec.code || ' ' || v_sec.year_level || v_sec.name
              || '. Your college is preparing your schedule.');
      RETURN v_sec.id;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

-- Move one student within the current term (from 20261025190000_withdrawals.sql).
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

  SELECT sec.id, sec.name, sec.year_level, sec.program_id, sec.school_year, sec.semester, p.code INTO v_sec
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
  IF NOT EXISTS (SELECT 1 FROM enrollment_term t
                  WHERE t.school_year = v_sec.school_year AND t.semester = v_sec.semester) THEN
    RAISE EXCEPTION 'Only a section of the current term can be used';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips
              WHERE student_id = p_student AND school_year = v_sec.school_year AND semester = v_sec.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the section can no longer be changed';
  END IF;

  SELECT section_id INTO v_old FROM student_sections
   WHERE student_id = p_student AND school_year = v_sec.school_year AND semester = v_sec.semester
     FOR UPDATE;
  IF v_old = p_section THEN
    RAISE EXCEPTION 'The student is already in this section';
  END IF;

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', v_reason, true);
  END IF;

  IF v_old IS NULL THEN
    INSERT INTO student_sections (student_id, section_id) VALUES (p_student, p_section);
  ELSE
    UPDATE student_sections SET section_id = p_section
     WHERE student_id = p_student AND school_year = v_sec.school_year AND semester = v_sec.semester;
  END IF;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user,
          CASE WHEN v_old IS NULL THEN 'section_placed' ELSE 'section_moved' END,
          CASE WHEN v_old IS NULL THEN 'Your section' ELSE 'Your section has changed' END,
          'You are placed in ' || v_sec.code || ' ' || v_sec.year_level || v_sec.name
          || '. Your college is preparing your schedule.');

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;
  RETURN p_section;
END;
$$;

-- ============================================================
-- 11. Assessment slip, per term
--     (from 20261025080000_assessment_slip.sql and 20261025180000_schedule_changes.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_slip_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_status  text;
  v_program uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue an assessment slip';
  END IF;
  SELECT s.schedule_status, e.school_year, e.semester
    INTO v_status, NEW.school_year, NEW.semester
    FROM student_enrollment(NEW.student_id) e
    JOIN sections s ON s.id = e.section_id;
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

-- The slip opens a pending payment for its own term when payment is required.
CREATE OR REPLACE FUNCTION open_payment_after_slip() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.payment_required THEN
    INSERT INTO payments (student_id, school_year, semester)
    VALUES (NEW.student_id, NEW.school_year, NEW.semester);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION issue_assessment_slip(p_student uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user     uuid;
  v_slip     uuid;
  v_required boolean;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue assessment slips';
  END IF;

  -- Two Registrars on the same student queue here; the second one then
  -- finds the slip and stops.
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student
     FOR UPDATE OF st;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;

  IF EXISTS (SELECT 1 FROM assessment_slips sl
               CROSS JOIN LATERAL student_enrollment(p_student) e
              WHERE sl.student_id = p_student AND sl.school_year = e.school_year AND sl.semester = e.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued';
  END IF;

  -- The gate trigger refuses unless the schedule is approved, and sets the term,
  -- payment_required (program toggle snapshot), the saved schedule, issued_by and issued_at.
  INSERT INTO assessment_slips (student_id, payment_required, issued_by)
  VALUES (p_student, false, current_actor_id())
  RETURNING id, payment_required INTO v_slip, v_required;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (
    v_user, 'slip_issued', 'Your assessment slip',
    CASE WHEN v_required
      THEN 'Your assessment slip is ready. Next, Finance clears your payment, then the Registrar issues your COR.'
      ELSE 'Your assessment slip is ready. Next, the Registrar issues your COR.'
    END
  );

  RETURN v_slip;
END;
$$;

-- Who is ready for a slip: placed in a section whose schedule is approved, no
-- slip for that term yet. Lowest student number first. One definition, used by
-- "Issue all" and by the Registrar's list.
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
   WHERE sec.schedule_status = 'approved'
     AND NOT EXISTS (SELECT 1 FROM assessment_slips sl
                      WHERE sl.student_id = st.id AND sl.school_year = e.school_year AND sl.semester = e.semester)
   ORDER BY st.student_number;
END;
$$;

CREATE OR REPLACE FUNCTION issue_all_ready_slips(OUT issued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue assessment slips';
  END IF;

  issued := 0;
  FOR r IN SELECT q.student_id FROM slip_ready_students() q
  LOOP
    PERFORM issue_assessment_slip(r.student_id);
    issued := issued + 1;
  END LOOP;
END;
$$;

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
           'section', p.code || ' ' || sec.year_level || sec.name,
           'issuedAt', sl.issued_at,
           'paymentRequired', sl.payment_required,
           'subjects', sl.schedule
         )
    INTO v_result
    FROM student_enrollment(p_student) sts
    JOIN assessment_slips sl ON sl.student_id = p_student
                            AND sl.school_year = sts.school_year AND sl.semester = sts.semester
    JOIN students st ON st.id = sl.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN sections sec ON sec.id = sts.section_id;

  RETURN v_result;
END;
$$;

-- ============================================================
-- 12. Payment, per term (from 20261025100000_payment.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION record_payment(
  p_student uuid, p_amount_due numeric, p_amount_paid numeric, p_receipt_no text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_payment payments%ROWTYPE;
  v_user    uuid;
  v_due     numeric;
  v_paid    numeric;
  v_receipt text := nullif(btrim(coalesce(p_receipt_no, '')), '');
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance or Admin can record a payment';
  END IF;

  IF p_amount_due IS NULL OR p_amount_due < 0 OR p_amount_due > 9999999999.99 THEN
    RAISE EXCEPTION 'Enter the amount due';
  END IF;
  IF p_amount_paid IS NULL OR p_amount_paid < 0 OR p_amount_paid > 9999999999.99 THEN
    RAISE EXCEPTION 'Enter the amount paid';
  END IF;
  v_due  := round(p_amount_due, 2);
  v_paid := round(p_amount_paid, 2);
  IF v_paid < v_due THEN
    RAISE EXCEPTION 'The amount paid must cover the amount due';
  END IF;
  IF v_paid > 0 AND v_receipt IS NULL THEN
    RAISE EXCEPTION 'Enter the receipt number';
  END IF;
  IF v_receipt IS NOT NULL AND length(v_receipt) > 60 THEN
    RAISE EXCEPTION 'The receipt number is longer than 60 characters';
  END IF;

  -- The payment of the student's current term. Two Finance staff on the same
  -- student queue here; the second one then finds it cleared and stops.
  SELECT pay.* INTO v_payment
    FROM student_enrollment(p_student) e
    JOIN payments pay ON pay.student_id = p_student
                     AND pay.school_year = e.school_year AND pay.semester = e.semester
     FOR UPDATE OF pay;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This student has no payment to record';
  END IF;
  IF v_payment.status = 'cleared' THEN
    RAISE EXCEPTION 'This payment was already recorded';
  END IF;

  -- The gate trigger stamps recorded_by and cleared_at on the way to cleared.
  UPDATE payments
     SET amount_due = v_due, amount_paid = v_paid, receipt_no = v_receipt, status = 'cleared'
   WHERE id = v_payment.id;

  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (
    v_user, 'payment_cleared', 'Your payment is cleared',
    'Finance recorded your payment. Next, the Registrar issues your COR.'
  );

  RETURN v_payment.id;
END;
$$;

-- One row per payment. The section shown is the one of the payment's own term.
CREATE OR REPLACE FUNCTION payment_queue(p_status text)
RETURNS TABLE (
  student_id     uuid,
  student_number text,
  full_name      text,
  program_code   text,
  section        text,
  amount_due     numeric,
  amount_paid    numeric,
  receipt_no     text,
  cleared_at     timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance or Admin can see payments';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('pending','cleared') THEN
    RAISE EXCEPTION 'Unknown payment status';
  END IF;

  RETURN QUERY
  SELECT st.id,
         st.student_number::text,
         u.full_name::text,
         p.code::text,
         (p.code || ' ' || sec.year_level || sec.name)::text,
         pay.amount_due::numeric,
         pay.amount_paid::numeric,
         pay.receipt_no::text,
         pay.cleared_at
    FROM payments pay
    JOIN students st ON st.id = pay.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    LEFT JOIN student_sections ss ON ss.student_id = st.id
                                 AND ss.school_year = pay.school_year AND ss.semester = pay.semester
    LEFT JOIN sections sec ON sec.id = ss.section_id
   WHERE pay.status = p_status
   ORDER BY (CASE WHEN pay.status = 'cleared' THEN pay.cleared_at END) DESC NULLS LAST,
            st.student_number;
END;
$$;

CREATE OR REPLACE FUNCTION my_payment_status() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT pay.status
    FROM student_enrollment(my_student_id()) e
    JOIN payments pay ON pay.student_id = my_student_id()
                     AND pay.school_year = e.school_year AND pay.semester = e.semester
$$;

-- ============================================================
-- 13. COR, per term
--     (from 20261025190000_withdrawals.sql, 20261025110000_cor.sql and
--      20261025180000_schedule_changes.sql)
-- ============================================================
-- The COR takes the term of the student's enrollment. It still needs the
-- current term to be set (an Admin step), as before.
CREATE OR REPLACE FUNCTION enforce_cor_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slip assessment_slips%ROWTYPE;
  v_term enrollment_term%ROWTYPE;
  v_e    student_sections%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue a COR';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = NEW.student_id AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;
  SELECT * INTO v_e FROM student_enrollment(NEW.student_id);
  SELECT * INTO v_slip FROM assessment_slips
   WHERE student_id = NEW.student_id AND school_year = v_e.school_year AND semester = v_e.semester;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The assessment slip must be issued before the COR';
  END IF;
  IF v_slip.payment_required AND NOT EXISTS (
       SELECT 1 FROM payments
        WHERE student_id = NEW.student_id AND school_year = v_e.school_year AND semester = v_e.semester
          AND status = 'cleared') THEN
    RAISE EXCEPTION 'Payment must be cleared before the COR';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them before issuing a COR';
  END IF;
  NEW.school_year := v_e.school_year;
  NEW.semester := v_e.semester;
  NEW.schedule := student_schedule_json(NEW.student_id);
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION issue_cor(p_student uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user  uuid;
  v_cor   uuid;
  v_year  text;
  v_sem   text;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue a COR';
  END IF;

  -- Two Registrars on the same student queue here; the second one then
  -- finds the COR and stops.
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student
     FOR UPDATE OF st;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;

  IF EXISTS (SELECT 1 FROM cors c
               CROSS JOIN LATERAL student_enrollment(p_student) e
              WHERE c.student_id = p_student AND c.school_year = e.school_year AND c.semester = e.semester) THEN
    RAISE EXCEPTION 'The COR was already issued';
  END IF;

  -- The gate trigger refuses without a slip, without cleared payment when it
  -- is required, or without a term, and sets the term, issued_by and issued_at.
  INSERT INTO cors (student_id, issued_by)
  VALUES (p_student, current_actor_id())
  RETURNING id, school_year, semester INTO v_cor, v_year, v_sem;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (
    v_user, 'cor_issued', 'You are officially enrolled',
    'You are officially enrolled for the ' ||
    CASE v_sem WHEN '1st' THEN '1st semester' WHEN '2nd' THEN '2nd semester' ELSE 'summer term' END ||
    ' of school year ' || v_year || '. Your Certificate of Registration is ready.'
  );

  RETURN v_cor;
END;
$$;

-- Who is ready for a COR: slip issued for the current enrollment's term,
-- payment cleared or not required, no COR for that term, not withdrawn.
CREATE OR REPLACE FUNCTION cor_ready_students()
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
    RAISE EXCEPTION 'Only the Registrar or Admin can see who is ready for a COR';
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
    JOIN assessment_slips sl ON sl.student_id = st.id AND sl.school_year = e.school_year AND sl.semester = e.semester
   WHERE a.withdrawn_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM cors c
                      WHERE c.student_id = st.id AND c.school_year = e.school_year AND c.semester = e.semester)
     AND (NOT sl.payment_required
          OR EXISTS (SELECT 1 FROM payments pay
                      WHERE pay.student_id = st.id AND pay.school_year = e.school_year
                        AND pay.semester = e.semester AND pay.status = 'cleared'))
   ORDER BY st.student_number;
END;
$$;

CREATE OR REPLACE FUNCTION issue_all_ready_cors(OUT issued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue a COR';
  END IF;

  issued := 0;
  FOR r IN SELECT q.student_id FROM cor_ready_students() q
  LOOP
    PERFORM issue_cor(r.student_id);
    issued := issued + 1;
  END LOOP;
END;
$$;

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
           'section', p.code || ' ' || sec.year_level || sec.name,
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
    FROM student_enrollment(p_student) sts
    JOIN cors c ON c.student_id = p_student AND c.school_year = sts.school_year AND c.semester = sts.semester
    JOIN students st ON st.id = c.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN colleges col ON col.id = p.college_id
    JOIN assessment_slips sl ON sl.student_id = st.id AND sl.school_year = c.school_year AND sl.semester = c.semester
    JOIN sections sec ON sec.id = sts.section_id
    JOIN users iu ON iu.id = c.issued_by
    LEFT JOIN payments pay ON pay.student_id = st.id AND pay.status = 'cleared'
                          AND pay.school_year = c.school_year AND pay.semester = c.semester;

  RETURN v_result;
END;
$$;

-- ============================================================
-- 14. Schedule changes, per term (from 20261025180000_schedule_changes.sql)
--     A section holds one term, so a COR of that term is what locks it.
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
               JOIN student_sections sts ON sts.student_id = c.student_id
                                        AND sts.school_year = c.school_year AND sts.semester = c.semester
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

-- True when the schedule saved on the slip of the student's current enrollment
-- differs from the current one and that term has no COR yet.
CREATE OR REPLACE FUNCTION my_schedule_changed() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((
    SELECT sl.schedule IS DISTINCT FROM student_schedule_json(sl.student_id)
           AND NOT EXISTS (SELECT 1 FROM cors c
                            WHERE c.student_id = sl.student_id
                              AND c.school_year = sl.school_year AND c.semester = sl.semester)
      FROM student_enrollment(my_student_id()) e
      JOIN assessment_slips sl ON sl.student_id = my_student_id()
                              AND sl.school_year = e.school_year AND sl.semester = e.semester
  ), false)
$$;

-- ============================================================
-- 15. Withdrawal releases only the current enrollment
--     (from 20261025190000_withdrawals.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION withdraw_enrollment_core(p_applicant uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_app     applicants%ROWTYPE;
  v_student uuid;
  v_year    text;
  v_sem     text;
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
    -- Only the current enrollment is released: its seat and its pending payment.
    -- Earlier terms stay as history.
    SELECT e.school_year, e.semester INTO v_year, v_sem FROM student_enrollment(v_student) e;

    DELETE FROM payments
     WHERE student_id = v_student AND status = 'pending'
       AND (v_year IS NULL OR (school_year = v_year AND semester = v_sem));

    IF v_year IS NOT NULL THEN
      DELETE FROM student_sections
       WHERE student_id = v_student AND school_year = v_year AND semester = v_sem;
      GET DIAGNOSTICS v_seats = ROW_COUNT;
      IF v_seats > 0 THEN
        -- The freed seat goes to the next student waiting for one.
        PERFORM place_waiting_students(v_app.program_id);
      END IF;
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

  -- Once the COR of the current enrollment is issued the enrollment is official:
  -- the Registrar records it.
  IF EXISTS (SELECT 1
               FROM students st
               CROSS JOIN LATERAL student_enrollment(st.id) e
               JOIN cors c ON c.student_id = st.id AND c.school_year = e.school_year AND c.semester = e.semester
              WHERE st.applicant_id = v_applicant) THEN
    RAISE EXCEPTION 'You are already enrolled. Ask the Registrar to withdraw you';
  END IF;

  RETURN withdraw_enrollment_core(v_applicant, p_reason);
END;
$$;

-- ============================================================
-- 16. The Admissions status queue: one stage per student, however many CORs
--     (from 20261025160000_admissions_status_queue.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION admissions_status_due(p_limit integer DEFAULT 5)
RETURNS TABLE (student_id uuid, applicant_ref varchar, student_number varchar, stage text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, a.applicant_ref, s.student_number,
         CASE WHEN EXISTS (SELECT 1 FROM cors c WHERE c.student_id = s.id) THEN 'enrolled' ELSE 'student' END
    FROM students s
    JOIN applicants a ON a.id = s.applicant_id
    LEFT JOIN admissions_status_queue q ON q.student_id = s.id
   WHERE q.stage_sent IS DISTINCT FROM
           (CASE WHEN EXISTS (SELECT 1 FROM cors c WHERE c.student_id = s.id) THEN 'enrolled' ELSE 'student' END)
     AND coalesce(q.attempts, 0) < 20
     AND (q.last_attempt_at IS NULL
          OR q.last_attempt_at <= now() - least(q.attempts, 12) * interval '5 minutes')
   ORDER BY coalesce(q.last_attempt_at, s.created_at), s.id
   LIMIT greatest(p_limit, 0)
$$;

-- ============================================================
-- 17. Who may call the new functions. The earlier grant migrations list
--     names, so the new ones are granted here. The helpers are internal.
-- ============================================================
REVOKE EXECUTE ON FUNCTION student_enrollment(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION slip_ready_students() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION cor_ready_students() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION current_term() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION student_enrollment(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION slip_ready_students() FROM anon;
    REVOKE EXECUTE ON FUNCTION cor_ready_students() FROM anon;
    REVOKE EXECUTE ON FUNCTION current_term() FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION student_enrollment(uuid) FROM authenticated;
    GRANT EXECUTE ON FUNCTION slip_ready_students() TO authenticated;
    GRANT EXECUTE ON FUNCTION cor_ready_students() TO authenticated;
    GRANT EXECUTE ON FUNCTION current_term() TO authenticated;
  END IF;
END $$;

-- The approved-schedule notification names the section as "BSIT 3A", like the rest.
CREATE OR REPLACE FUNCTION notify_schedule_approved() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_code text;
BEGIN
  SELECT code INTO v_code FROM programs WHERE id = NEW.program_id;
  INSERT INTO notifications (user_id, kind, title, message)
  SELECT a.user_id, 'schedule_approved', 'Your schedule is approved',
         'The schedule for ' || v_code || ' ' || NEW.year_level || NEW.name
         || ' is approved. Your next step is the assessment slip from the Registrar.'
    FROM student_sections ss
    JOIN students st ON st.id = ss.student_id
    JOIN applicants a ON a.id = st.applicant_id
   WHERE ss.section_id = NEW.id;
  RETURN NULL;
END;
$$;
