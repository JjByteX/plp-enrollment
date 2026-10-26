-- ============================================================
-- supabase/migrations/20261026040000_prerequisites_and_credits.sql
-- Step 20: prerequisites and credits.
--
-- Forward-only. Written from docs/step-18-returning-students-plan.md, decisions B, F, G and R.
--
--   - subject_prerequisites: a subject lists the earlier subjects a student must
--     have passed. All listed ones are required. No "either one" rules, no year
--     standing, no co-requisites. The subject and its prerequisites must be in the
--     same program, and a prerequisite must come earlier in the curriculum (a lower
--     year level, or the same year level and an earlier semester). A subject cannot
--     require itself and a loop is refused.
--   - student_credits: a subject credited to a student from earlier schooling
--     (a transferee's TOR). The Dean or the College Secretary records it with a
--     reason, the Registrar approves it. An approved credit counts as a pass and is
--     not a grade.
--   - student_has_passed, student_blocking_prerequisites, subject_eligibility: the
--     one definition of "may this student take this subject". Only a pass in an
--     approved grade sheet, or an approved credit, satisfies a prerequisite.
--     Incomplete, failed and dropped do not. Any passing attempt counts, so a retake
--     that passes unblocks the student. Steps 21 and 22 use this definition.
--
-- Writes go only through the functions below. A trigger refuses any other write to
-- the two new tables, Admin included. Everything is audited like the other tables.
-- A subject that other subjects require cannot be deleted, and the message names them.
-- ============================================================

-- ============================================================
-- 1. Tables
-- ============================================================
CREATE TABLE subject_prerequisites (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id      uuid NOT NULL REFERENCES subjects (id),
    prerequisite_id uuid NOT NULL REFERENCES subjects (id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (subject_id, prerequisite_id),
    CONSTRAINT subject_prerequisites_not_self CHECK (subject_id <> prerequisite_id)
);
CREATE INDEX idx_subject_prerequisites_required ON subject_prerequisites (prerequisite_id);
COMMENT ON TABLE subject_prerequisites IS 'A subject needs every listed prerequisite passed (or credited) before a student may take it.';

CREATE TABLE student_credits (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid NOT NULL REFERENCES students (id),
    subject_id      uuid NOT NULL REFERENCES subjects (id),
    reason          text NOT NULL CHECK (length(btrim(reason)) > 0),
    status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
    recorded_by     uuid NULL REFERENCES users (id),
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    decided_by      uuid NULL REFERENCES users (id),
    decided_at      timestamptz NULL,
    rejected_reason text NULL
);
-- One credit that is waiting or approved per student and subject. A rejected one can be recorded again.
CREATE UNIQUE INDEX student_credits_one_live ON student_credits (student_id, subject_id) WHERE status IN ('pending','approved');
CREATE INDEX idx_student_credits_student ON student_credits (student_id);
COMMENT ON TABLE student_credits IS 'A subject credited to a transferee. Dean or Secretary records, Registrar approves. An approved credit counts as a pass.';

-- ============================================================
-- 2. Direct writes are refused; the functions below turn the switch on
-- ============================================================
CREATE OR REPLACE FUNCTION refuse_direct_prerequisite_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.prereq_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Prerequisites and credits change only through their functions';
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
  FOREACH t IN ARRAY ARRAY['subject_prerequisites','student_credits'] LOOP
    EXECUTE format('CREATE TRIGGER trg_prerequisite_write_guard BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION refuse_direct_prerequisite_write()', t);
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION log_audit()', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY admin_all ON %I FOR ALL TO authenticated USING (app_role() = ''admin'') WITH CHECK (app_role() = ''admin'')', t);
  END LOOP;
END $$;

-- ============================================================
-- 3. Deleting a subject
-- ============================================================
-- A subject that other subjects require cannot be deleted, and the message names
-- them. A subject's own prerequisite rows go with it. Runs before the foreign key
-- check, so the person reads this sentence and not a database code.
CREATE OR REPLACE FUNCTION guard_subject_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_names text;
BEGIN
  SELECT string_agg(s.code, ', ' ORDER BY s.code) INTO v_names
    FROM subject_prerequisites sp
    JOIN subjects s ON s.id = sp.subject_id
   WHERE sp.prerequisite_id = OLD.id;
  IF v_names IS NOT NULL THEN
    RAISE EXCEPTION 'The subject % is a prerequisite of %. Remove it from those subjects first', OLD.code, v_names;
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  DELETE FROM subject_prerequisites WHERE subject_id = OLD.id;
  PERFORM set_config('app.prereq_write', 'off', true);
  RETURN OLD;
END;
$$;
CREATE TRIGGER trg_subject_delete_guard BEFORE DELETE ON subjects
    FOR EACH ROW EXECUTE FUNCTION guard_subject_delete();

-- ============================================================
-- 4. Eligibility: the one definition
-- ============================================================
-- Has the student passed the subject? A pass in an approved grade sheet, in any
-- attempt, or an approved credit. Internal: not granted to the app.
CREATE OR REPLACE FUNCTION student_has_passed(p_student uuid, p_subject uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
           SELECT 1 FROM grades g
             JOIN grade_sheets gs ON gs.id = g.sheet_id
            WHERE g.student_id = p_student AND g.subject_id = p_subject
              AND g.outcome = 'passed' AND gs.status = 'approved')
      OR EXISTS (
           SELECT 1 FROM student_credits c
            WHERE c.student_id = p_student AND c.subject_id = p_subject AND c.status = 'approved')
$$;

-- The prerequisites of a subject the student has not satisfied, each with where the
-- student stands on it: the outcome of the latest approved attempt, or not_taken.
-- Internal: not granted to the app.
CREATE OR REPLACE FUNCTION student_blocking_prerequisites(p_student uuid, p_subject uuid)
RETURNS TABLE (b_subject_id uuid, b_code text, b_title text, b_status text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.code::text, p.title::text,
         coalesce((SELECT g.outcome FROM grades g
                     JOIN grade_sheets gs ON gs.id = g.sheet_id
                    WHERE g.student_id = p_student AND g.subject_id = p.id AND gs.status = 'approved'
                    ORDER BY g.outcome_since DESC LIMIT 1), 'not_taken')
    FROM subject_prerequisites sp
    JOIN subjects p ON p.id = sp.prerequisite_id
   WHERE sp.subject_id = p_subject
     AND NOT student_has_passed(p_student, p.id)
   ORDER BY p.code
$$;

-- May this student take this subject? Staff only, and a Dean or Secretary only for a
-- student of their own college. Names every prerequisite that blocks.
CREATE OR REPLACE FUNCTION subject_eligibility(p_student uuid, p_subject uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_blocked jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('registrar','dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'You cannot check eligibility';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student) THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM subjects WHERE id = p_subject) THEN
    RAISE EXCEPTION 'That subject was not found';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'subjectId', b.b_subject_id, 'code', b.b_code, 'title', b.b_title, 'status', b.b_status) ORDER BY b.b_code), '[]'::jsonb)
    INTO v_blocked
    FROM student_blocking_prerequisites(p_student, p_subject) b;

  RETURN jsonb_build_object('allowed', jsonb_array_length(v_blocked) = 0, 'blockedBy', v_blocked);
END;
$$;

-- ============================================================
-- 5. The Prerequisites page
-- ============================================================
-- The programs the caller may open: every program for Admin and the Registrar, the
-- own college's programs for a Dean or a Secretary.
CREATE OR REPLACE FUNCTION prerequisite_programs() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin','registrar','dean','college_secretary') THEN
    RAISE EXCEPTION 'You cannot read prerequisites';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name) ORDER BY p.code)
      FROM programs p
     WHERE v_role IN ('admin','registrar') OR p.college_id = app_college_id()
  ), '[]'::jsonb);
END;
$$;

-- Every subject of one program with its prerequisites, in curriculum order.
CREATE OR REPLACE FUNCTION prerequisites_list(p_program uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin','registrar','dean','college_secretary') THEN
    RAISE EXCEPTION 'You cannot read prerequisites';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT program_in_my_college(p_program) THEN
    RAISE EXCEPTION 'That program is not in your college';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'subjectId', s.id,
             'code', s.code,
             'title', s.title,
             'yearLevel', s.year_level,
             'semester', s.semester,
             'prerequisites', coalesce((
               SELECT jsonb_agg(jsonb_build_object('subjectId', r.id, 'code', r.code, 'title', r.title) ORDER BY r.code)
                 FROM subject_prerequisites sp
                 JOIN subjects r ON r.id = sp.prerequisite_id
                WHERE sp.subject_id = s.id), '[]'::jsonb)
           ) ORDER BY s.year_level NULLS LAST, semester_rank(s.semester), s.code)
      FROM subjects s
     WHERE s.program_id = p_program
  ), '[]'::jsonb);
END;
$$;

-- Admin or the Dean of the program's college sets the whole list of one subject.
-- The refusals name the subjects involved.
CREATE OR REPLACE FUNCTION save_prerequisites(p_subject uuid, p_required uuid[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_sub subjects%ROWTYPE;
  v_req subjects%ROWTYPE;
  v_ids uuid[];
  v_id uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin','dean') THEN
    RAISE EXCEPTION 'Only Admin or the Dean of this college can set prerequisites';
  END IF;
  SELECT * INTO v_sub FROM subjects WHERE id = p_subject;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'That subject was not found';
  END IF;
  IF v_role = 'dean' AND NOT program_in_my_college(v_sub.program_id) THEN
    RAISE EXCEPTION 'Only the Dean of this college can set the prerequisites of this program';
  END IF;

  SELECT coalesce(array_agg(DISTINCT x), '{}'::uuid[]) INTO v_ids
    FROM unnest(coalesce(p_required, '{}'::uuid[])) AS x
   WHERE x IS NOT NULL;

  FOREACH v_id IN ARRAY v_ids LOOP
    SELECT * INTO v_req FROM subjects WHERE id = v_id;
    IF v_req.id IS NULL THEN
      RAISE EXCEPTION 'A required subject was not found';
    END IF;
    IF v_req.id = v_sub.id THEN
      RAISE EXCEPTION '% cannot require itself', v_sub.code;
    END IF;
    IF v_req.program_id <> v_sub.program_id THEN
      RAISE EXCEPTION '% is in another program. A prerequisite must be in the same program', v_req.code;
    END IF;
    IF v_req.year_level IS NULL OR v_sub.year_level IS NULL THEN
      RAISE EXCEPTION 'Set the year level of % and % first', v_sub.code, v_req.code;
    END IF;
    IF NOT (v_req.year_level < v_sub.year_level
            OR (v_req.year_level = v_sub.year_level AND semester_rank(v_req.semester) < semester_rank(v_sub.semester))) THEN
      RAISE EXCEPTION '% is not earlier in the curriculum than %', v_req.code, v_sub.code;
    END IF;
    IF EXISTS (
         WITH RECURSIVE up(id) AS (
           SELECT sp.prerequisite_id FROM subject_prerequisites sp WHERE sp.subject_id = v_id
           UNION
           SELECT sp.prerequisite_id FROM subject_prerequisites sp JOIN up ON sp.subject_id = up.id)
         SELECT 1 FROM up WHERE up.id = p_subject) THEN
      RAISE EXCEPTION '% already depends on %, so this would make a loop', v_req.code, v_sub.code;
    END IF;
  END LOOP;

  PERFORM set_config('app.prereq_write', 'on', true);
  DELETE FROM subject_prerequisites WHERE subject_id = p_subject AND NOT (prerequisite_id = ANY (v_ids));
  INSERT INTO subject_prerequisites (subject_id, prerequisite_id)
  SELECT p_subject, x FROM unnest(v_ids) AS x
  ON CONFLICT (subject_id, prerequisite_id) DO NOTHING;
  PERFORM set_config('app.prereq_write', 'off', true);
END;
$$;

-- ============================================================
-- 6. Credits
-- ============================================================
-- One student's credits, and the subjects of the student's program a credit could still
-- be recorded for (not passed, not credited, nothing waiting).
CREATE OR REPLACE FUNCTION credit_overview(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_program uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('registrar','dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'You cannot read credits';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students s JOIN applicants a ON a.id = s.applicant_id
   WHERE s.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;

  RETURN jsonb_build_object(
    'credits', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', c.id,
               'status', c.status,
               'code', sub.code,
               'title', sub.title,
               'reason', c.reason,
               'rejectedReason', c.rejected_reason,
               'recordedBy', (SELECT u.full_name FROM users u WHERE u.id = c.recorded_by),
               'recordedAt', c.recorded_at
             ) ORDER BY c.recorded_at)
        FROM student_credits c
        JOIN subjects sub ON sub.id = c.subject_id
       WHERE c.student_id = p_student), '[]'::jsonb),
    'options', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'subjectId', s.id, 'code', s.code, 'title', s.title, 'yearLevel', s.year_level
             ) ORDER BY s.year_level NULLS LAST, semester_rank(s.semester), s.code)
        FROM subjects s
       WHERE s.program_id = v_program
         AND NOT student_has_passed(p_student, s.id)
         AND NOT EXISTS (SELECT 1 FROM student_credits c WHERE c.student_id = p_student AND c.subject_id = s.id AND c.status = 'pending')
    ), '[]'::jsonb));
END;
$$;

-- The Dean or the Secretary records a credit. The reason names the line of the
-- transferee's TOR. It waits for the Registrar.
CREATE OR REPLACE FUNCTION record_credit(p_student uuid, p_subject uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_program uuid;
  v_sub subjects%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_id uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'Only the Dean or the College Secretary can record a credit';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students s JOIN applicants a ON a.id = s.applicant_id
   WHERE s.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  SELECT * INTO v_sub FROM subjects WHERE id = p_subject;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'That subject was not found';
  END IF;
  IF v_sub.program_id <> v_program THEN
    RAISE EXCEPTION '% is not in the student''s program', v_sub.code;
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  IF student_has_passed(p_student, p_subject) THEN
    RAISE EXCEPTION 'The student has already passed or been credited %', v_sub.code;
  END IF;
  IF EXISTS (SELECT 1 FROM student_credits c WHERE c.student_id = p_student AND c.subject_id = p_subject AND c.status = 'pending') THEN
    RAISE EXCEPTION 'A credit for % is already waiting for the Registrar', v_sub.code;
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  INSERT INTO student_credits (student_id, subject_id, reason, recorded_by)
  VALUES (p_student, p_subject, v_reason, current_actor_id())
  RETURNING id INTO v_id;
  PERFORM set_config('app.prereq_write', 'off', true);
  RETURN v_id;
END;
$$;

-- The credits waiting for the Registrar.
CREATE OR REPLACE FUNCTION credits_pending() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'You cannot read credits waiting for approval';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'id', c.id,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'program', p.code,
             'code', sub.code,
             'title', sub.title,
             'reason', c.reason,
             'recordedBy', (SELECT ru.full_name FROM users ru WHERE ru.id = c.recorded_by),
             'recordedAt', c.recorded_at
           ) ORDER BY c.recorded_at)
      FROM student_credits c
      JOIN students st ON st.id = c.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = a.program_id
      JOIN subjects sub ON sub.id = c.subject_id
     WHERE c.status = 'pending'
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION approve_credit(p_credit uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_credit student_credits%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can approve a credit';
  END IF;
  SELECT * INTO v_credit FROM student_credits WHERE id = p_credit FOR UPDATE;
  IF v_credit.id IS NULL OR v_credit.status <> 'pending' THEN
    RAISE EXCEPTION 'This credit is not waiting for approval';
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  UPDATE student_credits SET status = 'approved', decided_by = current_actor_id(), decided_at = now() WHERE id = p_credit;
  PERFORM set_config('app.prereq_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION reject_credit(p_credit uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_credit student_credits%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can reject a credit';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_credit FROM student_credits WHERE id = p_credit FOR UPDATE;
  IF v_credit.id IS NULL OR v_credit.status <> 'pending' THEN
    RAISE EXCEPTION 'This credit is not waiting for approval';
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  UPDATE student_credits
     SET status = 'rejected', decided_by = current_actor_id(), decided_at = now(), rejected_reason = v_reason
   WHERE id = p_credit;
  PERFORM set_config('app.prereq_write', 'off', true);
END;
$$;

-- ============================================================
-- 7. Who may call what
-- ============================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'student_has_passed(uuid, uuid)', 'student_blocking_prerequisites(uuid, uuid)', 'subject_eligibility(uuid, uuid)',
    'prerequisite_programs()', 'prerequisites_list(uuid)', 'save_prerequisites(uuid, uuid[])',
    'credit_overview(uuid)', 'record_credit(uuid, uuid, text)', 'credits_pending()',
    'approve_credit(uuid)', 'reject_credit(uuid, text)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', f);
    END IF;
  END LOOP;

  -- student_has_passed and student_blocking_prerequisites stay internal.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    FOREACH f IN ARRAY ARRAY[
      'subject_eligibility(uuid, uuid)', 'prerequisite_programs()', 'prerequisites_list(uuid)',
      'save_prerequisites(uuid, uuid[])', 'credit_overview(uuid)', 'record_credit(uuid, uuid, text)',
      'credits_pending()', 'approve_credit(uuid)', 'reject_credit(uuid, text)'
    ] LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END LOOP;
  END IF;
END $$;
