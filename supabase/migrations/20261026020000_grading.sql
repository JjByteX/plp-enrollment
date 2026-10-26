-- ============================================================
-- supabase/migrations/20261026020000_grading.sql
-- Step 19: grading scale and grades.
--
-- Forward-only. Written from docs/step-18-returning-students-plan.md, decisions A to E.
--
--   - grade_bands, grading_settings: the scale Admin sets. Nothing is seeded.
--     A band has a label, an outcome (passed, incomplete, failed, dropped) and,
--     for numeric grades, a from and to value. Descriptive bands are for display
--     only and never decide an outcome. The system never assumes a high or a low
--     number is better: the bands say it.
--   - grade_sheets, grades: one sheet per section and subject (draft, submitted,
--     approved) and one grade per enrolled student. A grade keeps the outcome
--     the band gave at the moment it was entered, so a later change of the scale
--     never rewrites it, and keeps the term it belongs to.
--   - grade_changes: the only way to change an approved grade. The Professor
--     proposes with a reason, the Dean signs, the Registrar approves.
--   - An incomplete (INC) that is not completed within the window becomes a
--     failed 5.0 by itself (lapse_incomplete_grades).
--
-- Every write goes through the functions below. A trigger refuses any other
-- write to these tables, Admin included, so an approved grade cannot be edited
-- by hand. Everything is audited like the other tables.
-- ============================================================

-- ============================================================
-- 1. Tables
-- ============================================================
CREATE TABLE grading_settings (
    id               boolean PRIMARY KEY DEFAULT true CHECK (id),
    inc_window_days  integer NOT NULL DEFAULT 14 CHECK (inc_window_days BETWEEN 1 AND 365),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
INSERT INTO grading_settings (id) VALUES (true);
COMMENT ON TABLE grading_settings IS 'One row. inc_window_days: how long an incomplete stays open after approval (charter default 14).';

CREATE TABLE grade_bands (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    label          varchar(30) NOT NULL,
    outcome        text NOT NULL CHECK (outcome IN ('passed','incomplete','failed','dropped')),
    is_descriptive boolean NOT NULL DEFAULT false,
    from_value     numeric(6,2) NULL,
    to_value       numeric(6,2) NULL,
    sort_order     integer NOT NULL DEFAULT 0,
    CONSTRAINT grade_bands_range_pair CHECK ((from_value IS NULL) = (to_value IS NULL)),
    CONSTRAINT grade_bands_range_order CHECK (from_value IS NULL OR from_value <= to_value),
    CONSTRAINT grade_bands_descriptive_passed CHECK (NOT is_descriptive OR outcome = 'passed')
);
CREATE UNIQUE INDEX grade_bands_label_key ON grade_bands (lower(label));
COMMENT ON TABLE grade_bands IS 'The grading scale. Descriptive bands (Excellent, Very Good ...) are display only and never change a rule.';

CREATE TABLE grade_sheets (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id    uuid NOT NULL REFERENCES sections (id) ON DELETE CASCADE,
    subject_id    uuid NOT NULL REFERENCES subjects (id),
    school_year   text NOT NULL,
    semester      text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','approved')),
    submitted_by  uuid NULL REFERENCES users (id),
    submitted_at  timestamptz NULL,
    approved_by   uuid NULL REFERENCES users (id),
    approved_at   timestamptz NULL,
    returned_reason text NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (section_id, subject_id)
);
COMMENT ON TABLE grade_sheets IS 'The grades of one subject in one section. draft (Professor edits), submitted (waits for the Dean), approved (locked).';

CREATE TABLE grades (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id      uuid NOT NULL REFERENCES grade_sheets (id) ON DELETE CASCADE,
    section_id    uuid NOT NULL REFERENCES sections (id) ON DELETE CASCADE,
    subject_id    uuid NOT NULL REFERENCES subjects (id),
    student_id    uuid NOT NULL REFERENCES students (id),
    school_year   text NOT NULL,
    semester      text NOT NULL,
    grade_text    text NOT NULL,
    outcome       text NOT NULL CHECK (outcome IN ('passed','incomplete','failed','dropped')),
    lapsed        boolean NOT NULL DEFAULT false,
    outcome_since timestamptz NOT NULL DEFAULT now(),
    entered_by    uuid NULL REFERENCES users (id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sheet_id, student_id)
);
CREATE INDEX idx_grades_student ON grades (student_id, school_year, semester);
COMMENT ON COLUMN grades.outcome IS 'Copied from the band when the grade was entered. A later change of the scale does not rewrite it.';
COMMENT ON COLUMN grades.outcome_since IS 'When the outcome took its present value (approval, a grade change, or a lapse). The INC window counts from here.';

CREATE TABLE grade_changes (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    grade_id         uuid NOT NULL REFERENCES grades (id) ON DELETE CASCADE,
    old_grade_text   text NOT NULL,
    old_outcome      text NOT NULL,
    new_grade_text   text NOT NULL,
    new_outcome      text NOT NULL,
    kind             text NOT NULL CHECK (kind IN ('correction','inc_completion','drop')),
    reason           text NOT NULL CHECK (length(btrim(reason)) > 0),
    status           text NOT NULL DEFAULT 'pending_dean'
                     CHECK (status IN ('pending_dean','pending_registrar','applied','rejected')),
    proposed_by      uuid NULL REFERENCES users (id),
    proposed_at      timestamptz NOT NULL DEFAULT now(),
    dean_by          uuid NULL REFERENCES users (id),
    dean_at          timestamptz NULL,
    registrar_by     uuid NULL REFERENCES users (id),
    registrar_at     timestamptz NULL,
    rejected_by      uuid NULL REFERENCES users (id),
    rejected_at      timestamptz NULL,
    rejected_reason  text NULL
);
CREATE UNIQUE INDEX grade_changes_one_open ON grade_changes (grade_id) WHERE status IN ('pending_dean','pending_registrar');
COMMENT ON TABLE grade_changes IS 'The only way to change an approved grade: Professor proposes, Dean signs, Registrar approves.';

-- ============================================================
-- 2. Direct writes are refused; the functions below turn the switch on
-- ============================================================
CREATE OR REPLACE FUNCTION refuse_direct_grade_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.grade_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Grades change only through the grading functions';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['grading_settings','grade_bands','grade_sheets','grades','grade_changes'] LOOP
    EXECUTE format('CREATE TRIGGER trg_grade_write_guard BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION refuse_direct_grade_write()', t);
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION log_audit()', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY admin_all ON %I FOR ALL TO authenticated USING (app_role() = ''admin'') WITH CHECK (app_role() = ''admin'')', t);
  END LOOP;
END $$;

-- ============================================================
-- 3. The scale
-- ============================================================
CREATE OR REPLACE FUNCTION grading_scale_ready() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM grade_bands b WHERE NOT b.is_descriptive)
$$;

-- A typed grade becomes one band: a number inside a numeric band, or a label
-- such as INC. Descriptive bands never match. No row means the grade is not on the scale.
CREATE OR REPLACE FUNCTION resolve_grade(p_text text) RETURNS TABLE (r_text text, r_outcome text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t text := btrim(coalesce(p_text, ''));
  v_n numeric;
BEGIN
  IF v_t = '' THEN
    RETURN;
  END IF;
  IF v_t ~ '^[0-9]{1,4}(\.[0-9]{1,2})?$' THEN
    v_n := v_t::numeric;
    RETURN QUERY
      SELECT v_t, b.outcome FROM grade_bands b
       WHERE NOT b.is_descriptive AND b.from_value IS NOT NULL AND v_n BETWEEN b.from_value AND b.to_value
       ORDER BY b.sort_order LIMIT 1;
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;
  RETURN QUERY
    SELECT b.label::text, b.outcome FROM grade_bands b
     WHERE NOT b.is_descriptive AND lower(b.label) = lower(v_t)
     ORDER BY b.sort_order LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION grading_scale() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('admin','professor','dean','registrar') THEN
    RAISE EXCEPTION 'You cannot read the grading scale';
  END IF;
  RETURN jsonb_build_object(
    'incWindowDays', (SELECT inc_window_days FROM grading_settings),
    'bands', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'label', b.label, 'outcome', b.outcome, 'descriptive', b.is_descriptive,
               'from', b.from_value, 'to', b.to_value) ORDER BY b.sort_order, b.label)
        FROM grade_bands b), '[]'::jsonb));
END;
$$;

-- Admin saves the whole scale at once. Two numeric bands that overlap are refused,
-- and the message names both.
CREATE OR REPLACE FUNCTION save_grade_scale(p_bands jsonb, p_inc_days integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  e jsonb;
  i integer := 0;
  v_label text;
  v_outcome text;
  v_desc boolean;
  v_from numeric;
  v_to numeric;
  v_a text;
  v_b text;
BEGIN
  IF app_role() IS NULL OR app_role() <> 'admin' THEN
    RAISE EXCEPTION 'Only Admin can set the grading scale';
  END IF;
  IF jsonb_typeof(p_bands) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'The bands are missing';
  END IF;
  IF p_inc_days IS NULL OR p_inc_days < 1 OR p_inc_days > 365 THEN
    RAISE EXCEPTION 'The incomplete window must be from 1 to 365 days';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  DELETE FROM grade_bands WHERE true;

  FOR e IN SELECT value FROM jsonb_array_elements(p_bands) LOOP
    i := i + 1;
    v_label := btrim(coalesce(e->>'label', ''));
    v_outcome := coalesce(e->>'outcome', '');
    v_desc := coalesce((e->>'descriptive')::boolean, false);
    v_from := nullif(e->>'from', '')::numeric;
    v_to := nullif(e->>'to', '')::numeric;
    IF v_label = '' OR length(v_label) > 30 THEN
      RAISE EXCEPTION 'Band % needs a label of 1 to 30 characters', i;
    END IF;
    IF v_outcome NOT IN ('passed','incomplete','failed','dropped') THEN
      RAISE EXCEPTION 'Band % needs an outcome', v_label;
    END IF;
    IF (v_from IS NULL) <> (v_to IS NULL) OR (v_from IS NOT NULL AND v_from > v_to) THEN
      RAISE EXCEPTION 'The range of band % is not valid', v_label;
    END IF;
    IF v_desc THEN
      v_outcome := 'passed';
    END IF;
    IF EXISTS (SELECT 1 FROM grade_bands WHERE lower(label) = lower(v_label)) THEN
      RAISE EXCEPTION 'Two bands are named %', v_label;
    END IF;
    INSERT INTO grade_bands (label, outcome, is_descriptive, from_value, to_value, sort_order)
    VALUES (v_label, v_outcome, v_desc, v_from, v_to, i);
  END LOOP;

  SELECT a.label, b.label INTO v_a, v_b
    FROM grade_bands a
    JOIN grade_bands b ON a.id < b.id
   WHERE NOT a.is_descriptive AND NOT b.is_descriptive
     AND a.from_value IS NOT NULL AND b.from_value IS NOT NULL
     AND a.from_value <= b.to_value AND b.from_value <= a.to_value
   LIMIT 1;
  IF v_a IS NOT NULL THEN
    RAISE EXCEPTION 'The bands % and % overlap', v_a, v_b;
  END IF;

  UPDATE grading_settings SET inc_window_days = p_inc_days, updated_at = now();
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

-- ============================================================
-- 4. Reading
-- ============================================================
CREATE OR REPLACE FUNCTION can_see_sheet(p_section uuid, p_subject uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE app_role()
    WHEN 'admin' THEN true
    WHEN 'registrar' THEN true
    WHEN 'dean' THEN section_in_my_college(p_section)
    WHEN 'professor' THEN EXISTS (
      SELECT 1 FROM section_subjects x
       WHERE x.section_id = p_section AND x.subject_id = p_subject AND x.professor_id = current_actor_id())
    ELSE false
  END
$$;

-- The subjects of the current term's sections the caller may open, each with its sheet status.
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
               'students', (SELECT count(*) FROM student_sections ss WHERE ss.section_id = sec.id),
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

-- One sheet: its status and one row per enrolled student.
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
        FROM student_sections ss
        JOIN students st ON st.id = ss.student_id
        JOIN applicants a ON a.id = st.applicant_id
        JOIN users u ON u.id = a.user_id
        LEFT JOIN grades g ON g.sheet_id = v_sheet.id AND g.student_id = st.id
       WHERE ss.section_id = p_section), '[]'::jsonb));
END;
$$;

-- ============================================================
-- 5. Entering, submitting and approving grades
-- ============================================================
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
    IF NOT EXISTS (SELECT 1 FROM student_sections ss WHERE ss.student_id = v_student AND ss.section_id = p_section) THEN
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
  IF NOT EXISTS (SELECT 1 FROM student_sections ss WHERE ss.section_id = p_section) THEN
    RAISE EXCEPTION 'This section has no students';
  END IF;
  SELECT st.student_number INTO v_missing
    FROM student_sections ss
    JOIN students st ON st.id = ss.student_id
   WHERE ss.section_id = p_section
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

-- The Dean approves, which locks the grades. Admin can do it too.
CREATE OR REPLACE FUNCTION approve_grades(p_section uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_sheet grade_sheets%ROWTYPE;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean of this college can approve grades';
  END IF;
  IF v_role = 'dean' AND NOT section_in_my_college(p_section) THEN
    RAISE EXCEPTION 'Only the Dean of this college can approve grades';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;
  IF v_sheet.id IS NULL OR v_sheet.status <> 'submitted' THEN
    RAISE EXCEPTION 'These grades are not waiting for approval';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_sheets SET status = 'approved', approved_by = current_actor_id(), approved_at = now() WHERE id = v_sheet.id;
  UPDATE grades SET outcome_since = now() WHERE sheet_id = v_sheet.id;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

-- The Dean sends submitted grades back to the Professor, with a reason.
CREATE OR REPLACE FUNCTION return_grades(p_section uuid, p_subject uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_sheet grade_sheets%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_label text;
  v_code text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean of this college can return grades';
  END IF;
  IF v_role = 'dean' AND NOT section_in_my_college(p_section) THEN
    RAISE EXCEPTION 'Only the Dean of this college can return grades';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;
  IF v_sheet.id IS NULL OR v_sheet.status <> 'submitted' THEN
    RAISE EXCEPTION 'These grades are not waiting for approval';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_sheets
     SET status = 'draft', submitted_by = NULL, submitted_at = NULL, returned_reason = v_reason
   WHERE id = v_sheet.id;
  PERFORM set_config('app.grade_write', 'off', true);

  SELECT p.code || ' ' || sec.year_level || sec.name, sub.code INTO v_label, v_code
    FROM sections sec JOIN programs p ON p.id = sec.program_id, subjects sub
   WHERE sec.id = p_section AND sub.id = p_subject;
  INSERT INTO notifications (user_id, kind, title, message)
  SELECT DISTINCT x.professor_id, 'grades_returned', 'Grades returned',
         'The Dean returned the grades for ' || v_code || ' in ' || v_label || '. Reason: ' || v_reason
    FROM section_subjects x
   WHERE x.section_id = p_section AND x.subject_id = p_subject AND x.professor_id IS NOT NULL;
END;
$$;

-- ============================================================
-- 6. Incomplete grades that run out of time
-- ============================================================
-- An approved INC older than the window becomes a failed 5.0. A grade with a
-- change waiting for a signature is left alone. Run when the Dean's or the
-- Registrar's Grades page opens, so no one has to press anything.
CREATE OR REPLACE FUNCTION lapse_incomplete_grades() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count integer;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','dean','admin') THEN
    RAISE EXCEPTION 'You cannot run this';
  END IF;
  PERFORM set_config('app.grade_write', 'on', true);
  WITH gone AS (
    UPDATE grades g
       SET grade_text = '5.0', outcome = 'failed', lapsed = true, outcome_since = now(), updated_at = now()
      FROM grade_sheets gs, grading_settings s
     WHERE gs.id = g.sheet_id AND gs.status = 'approved'
       AND g.outcome = 'incomplete'
       AND g.outcome_since + make_interval(days => s.inc_window_days) < now()
       AND NOT EXISTS (SELECT 1 FROM grade_changes c WHERE c.grade_id = g.id AND c.status IN ('pending_dean','pending_registrar'))
    RETURNING g.id)
  SELECT count(*) INTO v_count FROM gone;
  PERFORM set_config('app.grade_write', 'off', true);
  RETURN v_count;
END;
$$;

-- ============================================================
-- 7. Changing an approved grade: propose, sign, approve
-- ============================================================
CREATE OR REPLACE FUNCTION propose_grade_change(p_grade uuid, p_new_grade text, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_grade grades%ROWTYPE;
  v_sheet grade_sheets%ROWTYPE;
  v_res record;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_kind text;
  v_id uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','admin') THEN
    RAISE EXCEPTION 'Only the Professor of this subject can propose a grade change';
  END IF;
  SELECT * INTO v_grade FROM grades WHERE id = p_grade;
  IF v_grade.id IS NULL THEN
    RAISE EXCEPTION 'That grade was not found';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM section_subjects x
        WHERE x.section_id = v_grade.section_id AND x.subject_id = v_grade.subject_id
          AND (v_role = 'admin' OR x.professor_id = v_actor)) THEN
    RAISE EXCEPTION 'Only the Professor of this subject can propose a grade change';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE id = v_grade.sheet_id;
  IF v_sheet.status <> 'approved' THEN
    RAISE EXCEPTION 'The grades are not approved yet, so edit them directly';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_res FROM resolve_grade(p_new_grade);
  IF v_res.r_outcome IS NULL THEN
    RAISE EXCEPTION 'The grade "%" is not on the grading scale', btrim(coalesce(p_new_grade, ''));
  END IF;
  IF v_res.r_text = v_grade.grade_text THEN
    RAISE EXCEPTION 'The new grade is the same as the present grade';
  END IF;
  IF EXISTS (SELECT 1 FROM grade_changes c WHERE c.grade_id = p_grade AND c.status IN ('pending_dean','pending_registrar')) THEN
    RAISE EXCEPTION 'A change for this grade is already waiting';
  END IF;

  v_kind := CASE
    WHEN v_res.r_outcome = 'dropped' THEN 'drop'
    WHEN v_grade.outcome = 'incomplete' THEN 'inc_completion'
    ELSE 'correction' END;

  PERFORM set_config('app.grade_write', 'on', true);
  INSERT INTO grade_changes (grade_id, old_grade_text, old_outcome, new_grade_text, new_outcome, kind, reason, proposed_by)
  VALUES (p_grade, v_grade.grade_text, v_grade.outcome, v_res.r_text, v_res.r_outcome, v_kind, v_reason, v_actor)
  RETURNING id INTO v_id;
  PERFORM set_config('app.grade_write', 'off', true);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION sign_grade_change(p_change uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_change grade_changes%ROWTYPE;
  v_section uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean of this college can sign a grade change';
  END IF;
  SELECT * INTO v_change FROM grade_changes WHERE id = p_change FOR UPDATE;
  IF v_change.id IS NULL OR v_change.status <> 'pending_dean' THEN
    RAISE EXCEPTION 'This change is not waiting for the Dean';
  END IF;
  SELECT g.section_id INTO v_section FROM grades g WHERE g.id = v_change.grade_id;
  IF v_role = 'dean' AND NOT section_in_my_college(v_section) THEN
    RAISE EXCEPTION 'Only the Dean of this college can sign a grade change';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_changes SET status = 'pending_registrar', dean_by = current_actor_id(), dean_at = now() WHERE id = p_change;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION approve_grade_change(p_change uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_change grade_changes%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can approve a grade change';
  END IF;
  SELECT * INTO v_change FROM grade_changes WHERE id = p_change FOR UPDATE;
  IF v_change.id IS NULL OR v_change.status <> 'pending_registrar' THEN
    RAISE EXCEPTION 'This change is not waiting for the Registrar';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grades
     SET grade_text = v_change.new_grade_text, outcome = v_change.new_outcome, lapsed = false,
         outcome_since = now(), updated_at = now()
   WHERE id = v_change.grade_id;
  UPDATE grade_changes SET status = 'applied', registrar_by = current_actor_id(), registrar_at = now() WHERE id = p_change;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

-- The Dean rejects at the first step, the Registrar at the second. Admin at either.
CREATE OR REPLACE FUNCTION reject_grade_change(p_change uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_change grade_changes%ROWTYPE;
  v_section uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','registrar','admin') THEN
    RAISE EXCEPTION 'Only the Dean or the Registrar can reject a grade change';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_change FROM grade_changes WHERE id = p_change FOR UPDATE;
  IF v_change.id IS NULL OR v_change.status NOT IN ('pending_dean','pending_registrar') THEN
    RAISE EXCEPTION 'This change is not waiting for a decision';
  END IF;
  IF v_role = 'dean' THEN
    SELECT g.section_id INTO v_section FROM grades g WHERE g.id = v_change.grade_id;
    IF v_change.status <> 'pending_dean' OR NOT section_in_my_college(v_section) THEN
      RAISE EXCEPTION 'Only the Dean of this college can reject this change';
    END IF;
  ELSIF v_role = 'registrar' AND v_change.status <> 'pending_registrar' THEN
    RAISE EXCEPTION 'This change is waiting for the Dean first';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_changes
     SET status = 'rejected', rejected_by = current_actor_id(), rejected_at = now(), rejected_reason = v_reason
   WHERE id = p_change;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

-- The changes the caller can act on (Dean: waiting for the Dean in their college;
-- Registrar: waiting for the Registrar; Admin: all open) or, for a Professor, their own open ones.
CREATE OR REPLACE FUNCTION grade_changes_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_college uuid := app_college_id();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','dean','registrar','admin') THEN
    RAISE EXCEPTION 'You cannot read grade changes';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'id', c.id,
             'status', c.status,
             'kind', c.kind,
             'label', p.code || ' ' || sec.year_level || sec.name,
             'code', sub.code,
             'title', sub.title,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'oldGrade', c.old_grade_text,
             'oldOutcome', c.old_outcome,
             'newGrade', c.new_grade_text,
             'newOutcome', c.new_outcome,
             'reason', c.reason,
             'proposedBy', (SELECT pu.full_name FROM users pu WHERE pu.id = c.proposed_by),
             'proposedAt', c.proposed_at
           ) ORDER BY c.proposed_at)
      FROM grade_changes c
      JOIN grades g ON g.id = c.grade_id
      JOIN sections sec ON sec.id = g.section_id
      JOIN programs p ON p.id = sec.program_id
      JOIN subjects sub ON sub.id = g.subject_id
      JOIN students st ON st.id = g.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
     WHERE c.status IN ('pending_dean','pending_registrar')
       AND (v_role = 'admin'
            OR (v_role = 'dean' AND c.status = 'pending_dean' AND p.college_id = v_college)
            OR (v_role = 'registrar' AND c.status = 'pending_registrar')
            OR (v_role = 'professor' AND c.proposed_by = v_actor))
  ), '[]'::jsonb);
END;
$$;

-- ============================================================
-- 8. Who may call what
-- ============================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'grading_scale_ready()', 'resolve_grade(text)', 'can_see_sheet(uuid, uuid)',
    'grading_scale()', 'save_grade_scale(jsonb, integer)', 'grade_sections()', 'grade_sheet(uuid, uuid)',
    'save_grades(uuid, uuid, jsonb)', 'submit_grades(uuid, uuid)', 'approve_grades(uuid, uuid)',
    'return_grades(uuid, uuid, text)', 'lapse_incomplete_grades()',
    'propose_grade_change(uuid, text, text)', 'sign_grade_change(uuid)', 'approve_grade_change(uuid)',
    'reject_grade_change(uuid, text)', 'grade_changes_list()'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', f);
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    FOREACH f IN ARRAY ARRAY[
      'grading_scale()', 'save_grade_scale(jsonb, integer)', 'grade_sections()', 'grade_sheet(uuid, uuid)',
      'save_grades(uuid, uuid, jsonb)', 'submit_grades(uuid, uuid)', 'approve_grades(uuid, uuid)',
      'return_grades(uuid, uuid, text)', 'lapse_incomplete_grades()',
      'propose_grade_change(uuid, text, text)', 'sign_grade_change(uuid)', 'approve_grade_change(uuid)',
      'reject_grade_change(uuid, text)', 'grade_changes_list()'
    ] LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END LOOP;
  END IF;
END $$;
