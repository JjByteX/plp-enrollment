-- ============================================================
-- supabase/migrations/20261026070000_leave_of_absence.sql
-- Step 23: leave of absence and readmission.
--
-- Forward-only. Written from docs/step-18-returning-students-plan.md, decision U and step 23.
--
--   - leaves: one row per leave. Statuses: requested (recorded by the Secretary or Dean),
--     approved (by the Dean, the only human decision), active (the first leave term has opened and
--     the account is deactivated), ended (the return term has opened; the student waits for a load),
--     rejected. A leave is 1 or 2 regular terms (one academic year at most) and a student may use
--     4 regular terms in all (two academic years). A leave starts at a term boundary only.
--   - Deactivation and ending are automatic: leave_catch_up runs when Admin changes the term and
--     when a Schedules page loads. Nobody presses a button for them.
--   - The student is not placed automatically on return. A leave that has ended appears on the
--     needs review list. Placing the student in a section (the Dean's or Secretary's load) marks
--     the leave returned, reactivates the account and issues the readmission slip.
--   - A student with an approved or active leave is skipped by promotion (open_term) and by the
--     review list. A new student with no enrollment cannot take a leave.
--   - Replaced: open_term (from 20261026050000) and review_students (from 20261026050000).
--
-- Writes to leaves go only through the functions below. A trigger refuses any other write,
-- Admin included. Everything is audited like the other tables.
-- ============================================================

-- ============================================================
-- 1. Term helpers (internal)
-- ============================================================
CREATE OR REPLACE FUNCTION term_order(p_year text, p_semester text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT left(p_year, 4)::integer * 4 + semester_rank(p_semester)
$$;

-- The regular term after a regular term (summer is skipped).
CREATE OR REPLACE FUNCTION next_regular_term(p_year text, p_semester text)
RETURNS TABLE (next_year text, next_semester text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester
           WHEN '1st' THEN p_year
           ELSE (left(p_year, 4)::integer + 1)::text || '-' || (left(p_year, 4)::integer + 2)::text
         END,
         CASE p_semester WHEN '1st' THEN '2nd' ELSE '1st' END
   WHERE p_semester IN ('1st','2nd') AND p_year ~ '^[0-9]{4}-[0-9]{4}$'
$$;

-- The regular term a leave of p_terms regular terms returns in.
CREATE OR REPLACE FUNCTION leave_return_term(p_year text, p_semester text, p_terms integer)
RETURNS TABLE (return_year text, return_semester text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_year text := p_year;
  v_sem  text := p_semester;
  i      integer;
BEGIN
  FOR i IN 1..p_terms LOOP
    SELECT n.next_year, n.next_semester INTO v_year, v_sem FROM next_regular_term(v_year, v_sem) n;
  END LOOP;
  RETURN QUERY SELECT v_year, v_sem;
END;
$$;

-- Does a leave from (start) up to but not including (return) cover the term? A summer term
-- between the two is covered.
CREATE OR REPLACE FUNCTION leave_covers_term(
  p_start_year text, p_start_semester text, p_return_year text, p_return_semester text,
  p_year text, p_semester text
) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT term_order(p_year, p_semester) >= term_order(p_start_year, p_start_semester)
     AND term_order(p_year, p_semester) <  term_order(p_return_year, p_return_semester)
$$;

CREATE OR REPLACE FUNCTION term_text(p_year text, p_semester text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester WHEN 'summer' THEN 'summer' ELSE p_semester || ' semester' END || ' of school year ' || p_year
$$;

-- ============================================================
-- 2. The table
-- ============================================================
CREATE TABLE leaves (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL REFERENCES students (id),
    start_year       text NOT NULL CHECK (start_year ~ '^[0-9]{4}-[0-9]{4}$'),
    start_semester   text NOT NULL CHECK (start_semester IN ('1st','2nd')),
    terms            smallint NOT NULL CHECK (terms IN (1, 2)),
    return_year      text NOT NULL CHECK (return_year ~ '^[0-9]{4}-[0-9]{4}$'),
    return_semester  text NOT NULL CHECK (return_semester IN ('1st','2nd')),
    reason           text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
    status           text NOT NULL DEFAULT 'requested'
                     CHECK (status IN ('requested','approved','active','ended','rejected')),
    recorded_by      uuid NULL REFERENCES users (id),
    recorded_at      timestamptz NOT NULL DEFAULT now(),
    decided_by       uuid NULL REFERENCES users (id),
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    activated_at     timestamptz NULL,
    ended_at         timestamptz NULL,
    returned_at      timestamptz NULL,
    returned_year    text NULL,
    returned_semester text NULL,
    readmitted_by    uuid NULL REFERENCES users (id)
);
CREATE INDEX idx_leaves_student ON leaves (student_id);
-- One unfinished leave per student: requested, approved, active, or ended and not yet returned.
CREATE UNIQUE INDEX leaves_one_open ON leaves (student_id)
    WHERE status IN ('requested','approved','active') OR (status = 'ended' AND returned_at IS NULL);
COMMENT ON TABLE leaves IS 'A leave of absence. Staff record it, the Dean approves, the system activates and ends it. returned_at is set when the student is placed in a section again.';

CREATE OR REPLACE FUNCTION refuse_direct_leave_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.leave_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'A leave of absence changes only through the leave functions';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_leave_write_guard BEFORE INSERT OR UPDATE OR DELETE ON leaves
    FOR EACH ROW EXECUTE FUNCTION refuse_direct_leave_write();
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON leaves
    FOR EACH ROW EXECUTE FUNCTION log_audit();
ALTER TABLE leaves ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_all ON leaves FOR ALL TO authenticated
    USING (app_role() = 'admin') WITH CHECK (app_role() = 'admin');

-- ============================================================
-- 3. Small helpers (internal)
-- ============================================================
-- Regular terms of approved leave a student has used or holds (cap: 4, two academic years).
CREATE OR REPLACE FUNCTION leave_terms_used(p_student uuid) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(sum(l.terms), 0)::integer
    FROM leaves l
   WHERE l.student_id = p_student AND l.status IN ('approved','active','ended')
$$;

CREATE OR REPLACE FUNCTION leave_json(l leaves) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'id', l.id, 'status', l.status,
    'startYear', l.start_year, 'startSemester', l.start_semester, 'terms', l.terms,
    'returnYear', l.return_year, 'returnSemester', l.return_semester,
    'reason', l.reason, 'decisionNote', l.decision_note,
    'returned', l.returned_at IS NOT NULL)
$$;

-- ============================================================
-- 4. Guard: nobody is placed in a term an approved or active leave covers
-- ============================================================
CREATE OR REPLACE FUNCTION leave_guard_enrollment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  l leaves%ROWTYPE;
BEGIN
  SELECT * INTO l FROM leaves x
   WHERE x.student_id = NEW.student_id AND x.status IN ('approved','active')
     AND leave_covers_term(x.start_year, x.start_semester, x.return_year, x.return_semester, NEW.school_year, NEW.semester);
  IF FOUND THEN
    RAISE EXCEPTION 'This student is on leave of absence until the %',
      term_text(l.return_year, l.return_semester);
  END IF;
  RETURN NEW;
END;
$$;
-- Named to fire after trg_student_sections_term, which fills in the term from the section.
CREATE TRIGGER trg_student_sections_x_leave_guard BEFORE INSERT ON student_sections
    FOR EACH ROW EXECUTE FUNCTION leave_guard_enrollment();

-- ============================================================
-- 5. Automatic steps: activate, end, and return
-- ============================================================
CREATE OR REPLACE FUNCTION run_leave_catch_up() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_term enrollment_term%ROWTYPE;
  r      record;
  v_n    integer := 0;
BEGIN
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  PERFORM set_config('app.leave_write', 'on', true);

  -- Approved leaves whose first term has opened: the account is deactivated.
  FOR r IN
    SELECT l.id, a.user_id
      FROM leaves l
      JOIN students st ON st.id = l.student_id
      JOIN applicants a ON a.id = st.applicant_id
     WHERE l.status = 'approved' AND a.withdrawn_at IS NULL
       AND term_order(v_term.school_year, v_term.semester) >= term_order(l.start_year, l.start_semester)
       FOR UPDATE OF l
  LOOP
    UPDATE leaves SET status = 'active', activated_at = now() WHERE id = r.id;
    UPDATE users SET is_active = false WHERE id = r.user_id;
    v_n := v_n + 1;
  END LOOP;

  -- Active leaves whose return term has opened: the leave ends and the student waits for a load.
  FOR r IN
    SELECT l.id
      FROM leaves l
     WHERE l.status = 'active'
       AND term_order(v_term.school_year, v_term.semester) >= term_order(l.return_year, l.return_semester)
       FOR UPDATE OF l
  LOOP
    UPDATE leaves SET status = 'ended', ended_at = now() WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;

  PERFORM set_config('app.leave_write', 'off', true);
  RETURN v_n;
END;
$$;

-- The same catch-up for a Schedules page load.
CREATE OR REPLACE FUNCTION leave_catch_up() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'You cannot run the leave catch up';
  END IF;
  RETURN run_leave_catch_up();
END;
$$;

CREATE OR REPLACE FUNCTION after_term_changed_leaves() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM run_leave_catch_up();
  RETURN NULL;
END;
$$;
-- Named to fire before trg_enrollment_term_open (promotion).
CREATE TRIGGER trg_enrollment_term_leaves AFTER UPDATE ON enrollment_term
    FOR EACH ROW
    WHEN (OLD.school_year IS DISTINCT FROM NEW.school_year OR OLD.semester IS DISTINCT FROM NEW.semester)
    EXECUTE FUNCTION after_term_changed_leaves();

-- A student of an ended leave placed in a section is back: the leave is marked returned, the
-- account is active again and the readmission slip is issued (it reads this row).
CREATE OR REPLACE FUNCTION leave_after_enrollment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  l      leaves%ROWTYPE;
  v_user uuid;
BEGIN
  SELECT * INTO l FROM leaves x
   WHERE x.student_id = NEW.student_id AND x.status = 'ended' AND x.returned_at IS NULL
     FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = NEW.student_id;

  PERFORM set_config('app.leave_write', 'on', true);
  UPDATE leaves
     SET returned_at = now(), returned_year = NEW.school_year, returned_semester = NEW.semester,
         readmitted_by = current_actor_id()
   WHERE id = l.id;
  PERFORM set_config('app.leave_write', 'off', true);

  UPDATE users SET is_active = true WHERE id = v_user;
  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'readmitted', 'Welcome back',
          'Your account is active again and your readmission slip is ready. Your college is preparing your schedule for the '
          || term_text(NEW.school_year, NEW.semester) || '.');
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_student_sections_returned AFTER INSERT ON student_sections
    FOR EACH ROW EXECUTE FUNCTION leave_after_enrollment();

-- ============================================================
-- 6. Recording, deciding
-- ============================================================
CREATE OR REPLACE FUNCTION record_leave(
  p_student uuid, p_year text, p_semester text, p_terms integer, p_reason text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role   text := app_role();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_term   enrollment_term%ROWTYPE;
  v_ret    record;
  v_used   integer;
  v_id     uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary or the Dean can record a leave of absence';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student) THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = p_student AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  IF p_semester IS NULL OR p_semester NOT IN ('1st','2nd') OR p_year IS NULL OR p_year !~ '^[0-9]{4}-[0-9]{4}$' THEN
    RAISE EXCEPTION 'A leave starts at the 1st or 2nd semester of a school year';
  END IF;
  IF p_terms IS NULL OR p_terms NOT IN (1, 2) THEN
    RAISE EXCEPTION 'A leave lasts one or two terms, one academic year at most';
  END IF;

  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF term_order(p_year, p_semester) < term_order(v_term.school_year, v_term.semester) THEN
    RAISE EXCEPTION 'A leave cannot start before the current term';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM student_sections WHERE student_id = p_student) THEN
    RAISE EXCEPTION 'This student has no enrollment yet, so there is nothing to leave. A new student can withdraw instead';
  END IF;
  IF EXISTS (SELECT 1 FROM student_sections ss
              WHERE ss.student_id = p_student
                AND term_order(ss.school_year, ss.semester) >= term_order(p_year, p_semester)) THEN
    RAISE EXCEPTION 'The student is already placed in the % or later. Choose a later first term',
      term_text(p_year, p_semester);
  END IF;
  IF EXISTS (SELECT 1 FROM leaves l WHERE l.student_id = p_student
              AND (l.status IN ('requested','approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL))) THEN
    RAISE EXCEPTION 'This student already has a leave that is not finished';
  END IF;
  v_used := leave_terms_used(p_student);
  IF v_used + p_terms > 4 THEN
    RAISE EXCEPTION 'This leave would pass two academic years in all. The student has used % of 4 terms', v_used;
  END IF;

  SELECT r.return_year, r.return_semester INTO v_ret FROM leave_return_term(p_year, p_semester, p_terms) r;

  PERFORM set_config('app.leave_write', 'on', true);
  INSERT INTO leaves (student_id, start_year, start_semester, terms, return_year, return_semester, reason, recorded_by)
  VALUES (p_student, p_year, p_semester, p_terms, v_ret.return_year, v_ret.return_semester, v_reason, current_actor_id())
  RETURNING id INTO v_id;
  PERFORM set_config('app.leave_write', 'off', true);
  RETURN v_id;
END;
$$;

-- The Dean's decision, the only human one.
CREATE OR REPLACE FUNCTION decide_leave(p_leave uuid, p_approve boolean, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  l      leaves%ROWTYPE;
  v_term enrollment_term%ROWTYPE;
  v_user uuid;
  v_used integer;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean can decide a leave of absence';
  END IF;
  SELECT * INTO l FROM leaves WHERE id = p_leave FOR UPDATE;
  IF l.id IS NULL OR l.status <> 'requested' THEN
    RAISE EXCEPTION 'This leave is not waiting for a decision';
  END IF;
  IF v_role = 'dean' AND NOT student_in_my_college(l.student_id) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  IF v_note IS NOT NULL AND length(v_note) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  SELECT a.user_id INTO v_user FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = l.student_id;

  IF NOT p_approve THEN
    IF v_note IS NULL THEN
      RAISE EXCEPTION 'Enter the reason';
    END IF;
    PERFORM set_config('app.leave_write', 'on', true);
    UPDATE leaves SET status = 'rejected', decided_by = current_actor_id(), decided_at = now(), decision_note = v_note
     WHERE id = l.id;
    PERFORM set_config('app.leave_write', 'off', true);
    IF l.recorded_by IS NOT NULL THEN
      INSERT INTO notifications (user_id, kind, title, message)
      VALUES (l.recorded_by, 'leave_rejected', 'Leave of absence not approved',
              'The leave from the ' || term_text(l.start_year, l.start_semester) || ' was not approved: ' || v_note);
    END IF;
    RETURN;
  END IF;

  -- Approval checks everything again: time may have passed since it was recorded.
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF term_order(l.start_year, l.start_semester) < term_order(v_term.school_year, v_term.semester) THEN
    RAISE EXCEPTION 'The first term of this leave has passed. Reject it and record a new one';
  END IF;
  IF EXISTS (SELECT 1 FROM student_sections ss
              WHERE ss.student_id = l.student_id
                AND term_order(ss.school_year, ss.semester) >= term_order(l.start_year, l.start_semester)) THEN
    RAISE EXCEPTION 'The student is already placed in the % or later. Reject it and record a later start',
      term_text(l.start_year, l.start_semester);
  END IF;
  v_used := leave_terms_used(l.student_id);
  IF v_used + l.terms > 4 THEN
    RAISE EXCEPTION 'This leave would pass two academic years in all. The student has used % of 4 terms', v_used;
  END IF;

  PERFORM set_config('app.leave_write', 'on', true);
  UPDATE leaves SET status = 'approved', decided_by = current_actor_id(), decided_at = now(), decision_note = v_note
   WHERE id = l.id;
  PERFORM set_config('app.leave_write', 'off', true);

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'leave_approved', 'Leave of absence approved',
          'Your leave of absence starts with the ' || term_text(l.start_year, l.start_semester)
          || ' and you return in the ' || term_text(l.return_year, l.return_semester)
          || '. Your account is deactivated while you are on leave. Your college builds your subjects when you return.');

  -- A leave that starts in the current term takes effect now.
  PERFORM run_leave_catch_up();
END;
$$;

-- ============================================================
-- 7. Reading
-- ============================================================
-- One student's leaves, for the record window.
CREATE OR REPLACE FUNCTION leave_overview(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_term enrollment_term%ROWTYPE;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read leaves of absence';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student) THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  RETURN jsonb_build_object(
    'term', CASE WHEN v_term.school_year IS NULL THEN NULL
                 ELSE jsonb_build_object('schoolYear', v_term.school_year, 'semester', v_term.semester) END,
    'used', leave_terms_used(p_student),
    'hasEnrollment', EXISTS (SELECT 1 FROM student_sections WHERE student_id = p_student),
    'open', EXISTS (SELECT 1 FROM leaves l WHERE l.student_id = p_student
                     AND (l.status IN ('requested','approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL))),
    'leaves', coalesce((SELECT jsonb_agg(leave_json(l) ORDER BY l.recorded_at) FROM leaves l WHERE l.student_id = p_student), '[]'::jsonb));
END;
$$;

-- Leaves waiting for the Dean, for the Changes tab.
CREATE OR REPLACE FUNCTION leave_requests() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean can read leaves waiting for approval';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(leave_json(l) || jsonb_build_object(
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'usedTerms', leave_terms_used(l.student_id),
             'recordedBy', (SELECT ru.full_name FROM users ru WHERE ru.id = l.recorded_by),
             'recordedAt', l.recorded_at
           ) ORDER BY l.recorded_at)
      FROM leaves l
      JOIN students st ON st.id = l.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = a.program_id
     WHERE l.status = 'requested' AND a.withdrawn_at IS NULL
       AND (v_role = 'admin' OR p.college_id = app_college_id())
  ), '[]'::jsonb);
END;
$$;

-- The Registrar's read-only list: students whose leave is approved, running, or ended and
-- not yet returned, with the return term.
CREATE OR REPLACE FUNCTION students_on_leave() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can read the students on leave';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(leave_json(l) || jsonb_build_object(
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'approvedBy', (SELECT du.full_name FROM users du WHERE du.id = l.decided_by)
           ) ORDER BY l.return_year, semester_rank(l.return_semester), st.student_number)
      FROM leaves l
      JOIN students st ON st.id = l.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = a.program_id
     WHERE (l.status IN ('approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL))
       AND a.withdrawn_at IS NULL
  ), '[]'::jsonb);
END;
$$;

-- A student with an approved leave that has not started yet, for the next step card.
CREATE OR REPLACE FUNCTION my_leave() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT leave_json(l)
    FROM leaves l
   WHERE l.student_id = my_student_id() AND l.status = 'approved'
   LIMIT 1
$$;

-- The readmission slip of the student's latest return.
CREATE OR REPLACE FUNCTION my_readmission() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
           'studentNumber', st.student_number,
           'fullName', u.full_name,
           'programCode', p.code,
           'programName', p.name,
           'section', (SELECT pr.code || ' ' || sec.year_level || sec.name
                         FROM student_sections ss
                         JOIN sections sec ON sec.id = ss.section_id
                         JOIN programs pr ON pr.id = sec.program_id
                        WHERE ss.student_id = st.id AND ss.school_year = l.returned_year AND ss.semester = l.returned_semester),
           'startYear', l.start_year, 'startSemester', l.start_semester, 'terms', l.terms,
           'returnYear', l.return_year, 'returnSemester', l.return_semester,
           'returnedYear', l.returned_year, 'returnedSemester', l.returned_semester,
           'returnedAt', l.returned_at,
           'approvedBy', (SELECT du.full_name FROM users du WHERE du.id = l.decided_by),
           'readmittedBy', (SELECT ru.full_name FROM users ru WHERE ru.id = l.readmitted_by))
    FROM leaves l
    JOIN students st ON st.id = l.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
   WHERE st.id = my_student_id() AND l.returned_at IS NOT NULL
   ORDER BY l.returned_at DESC
   LIMIT 1
$$;

-- ============================================================
-- 8. The review list also shows students whose leave ended (from 20261026050000_close_term.sql)
--    and no longer shows students who are on leave. A returning student has a kind of 'leave'.
-- ============================================================
CREATE OR REPLACE FUNCTION review_students() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read the review list';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(q.item ORDER BY q.program_code, q.student_number)
      FROM (
        SELECT p.code AS program_code, st.student_number,
               jsonb_build_object(
                 'kind', 'review',
                 'studentId', st.id,
                 'studentNumber', st.student_number,
                 'fullName', u.full_name,
                 'programCode', p.code,
                 'yearLevel', tr.year_level,
                 'schoolYear', tr.school_year,
                 'semester', tr.semester,
                 'reason', coalesce(tr.reason, '')
               ) AS item
          FROM term_results tr
          JOIN students st ON st.id = tr.student_id
          JOIN applicants a ON a.id = st.applicant_id
          JOIN users u ON u.id = a.user_id
          JOIN programs p ON p.id = tr.program_id
         WHERE tr.result = 'review'
           AND a.withdrawn_at IS NULL
           AND NOT has_enrollment_after(tr.student_id, tr.school_year, tr.semester)
           AND (v_role = 'admin' OR program_in_my_college(tr.program_id))
           AND NOT EXISTS (SELECT 1 FROM leaves l
                            WHERE l.student_id = tr.student_id
                              AND (l.status IN ('approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL)))
        UNION ALL
        SELECT p.code, st.student_number,
               jsonb_build_object(
                 'kind', 'leave',
                 'studentId', st.id,
                 'studentNumber', st.student_number,
                 'fullName', u.full_name,
                 'programCode', p.code,
                 'yearLevel', coalesce(lastsec.year_level, 0),
                 'schoolYear', l.return_year,
                 'semester', l.return_semester,
                 'reason', CASE WHEN leave_terms_used(st.id) >= 4
                                THEN 'Two years of leave used'
                                ELSE 'Returning from leave' END
               )
          FROM leaves l
          JOIN students st ON st.id = l.student_id
          JOIN applicants a ON a.id = st.applicant_id
          JOIN users u ON u.id = a.user_id
          JOIN programs p ON p.id = a.program_id
          LEFT JOIN LATERAL (
            SELECT sec.year_level
              FROM student_sections ss JOIN sections sec ON sec.id = ss.section_id
             WHERE ss.student_id = st.id
             ORDER BY ss.school_year DESC, semester_rank(ss.semester) DESC
             LIMIT 1) lastsec ON true
         WHERE l.status = 'ended' AND l.returned_at IS NULL
           AND a.withdrawn_at IS NULL
           AND (v_role = 'admin' OR p.college_id = app_college_id())
      ) q
  ), '[]'::jsonb);
END;
$$;

-- ============================================================
-- 9. Promotion skips a student on leave (from 20261026050000_close_term.sql)
--    The only change is the leave check in the seating loop.
-- ============================================================
CREATE OR REPLACE FUNCTION open_term(p_year text, p_semester text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_prev_year  text;
  v_prev_sem   text;
  v_closure    term_closures%ROWTYPE;
  r            record;
  v_next_year  integer;
  v_sec_id     uuid;
  v_sec_name   varchar;
  v_term_text  text;
BEGIN
  IF p_semester NOT IN ('1st','2nd') THEN
    RETURN;
  END IF;
  SELECT pr.prev_year, pr.prev_semester INTO v_prev_year, v_prev_sem FROM previous_regular_term(p_year, p_semester) pr;
  IF v_prev_year IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_closure FROM term_closures c
   WHERE c.school_year = v_prev_year AND c.semester = v_prev_sem
     FOR UPDATE;
  IF NOT FOUND OR v_closure.opened_at IS NOT NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('app.term_write', 'on', true);

  IF p_semester = '2nd' THEN
    INSERT INTO sections (program_id, name, year_level, capacity, school_year, semester)
    SELECT s.program_id, s.name, s.year_level, s.capacity, p_year, p_semester
      FROM sections s
     WHERE s.school_year = v_prev_year AND s.semester = v_prev_sem
    ON CONFLICT ON CONSTRAINT sections_term_name_key DO NOTHING;
  ELSE
    INSERT INTO sections (program_id, name, year_level, capacity, school_year, semester)
    SELECT x.program_id, x.name, x.year_level, x.capacity, p_year, p_semester
      FROM (
        SELECT s.program_id, s.name, 1 AS year_level, s.capacity
          FROM sections s
         WHERE s.school_year = v_prev_year AND s.semester = v_prev_sem AND s.year_level = 1
        UNION
        SELECT s.program_id, s.name, s.year_level + 1, s.capacity
          FROM sections s
         WHERE s.school_year = v_prev_year AND s.semester = v_prev_sem
           AND s.year_level + 1 <= coalesce((SELECT max(sub.year_level) FROM subjects sub WHERE sub.program_id = s.program_id), 0)
      ) x
    ON CONFLICT ON CONSTRAINT sections_term_name_key DO NOTHING;
  END IF;

  v_term_text := CASE p_semester WHEN '1st' THEN '1st semester' ELSE '2nd semester' END || ' of school year ' || p_year;

  FOR r IN
    SELECT tr.student_id, tr.program_id, tr.year_level, tr.section_name, a.user_id, a.withdrawn_at, p.code AS program_code
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN programs p ON p.id = tr.program_id
     WHERE tr.school_year = v_prev_year AND tr.semester = v_prev_sem
       AND tr.result = 'promote' AND tr.placed_at IS NULL
     ORDER BY st.student_number
  LOOP
    IF r.withdrawn_at IS NOT NULL THEN
      CONTINUE;
    END IF;

    -- A student on leave is not seated; they return through the review list (step 23).
    IF EXISTS (SELECT 1 FROM leaves l
                WHERE l.student_id = r.student_id AND l.status IN ('approved','active')
                  AND leave_covers_term(l.start_year, l.start_semester, l.return_year, l.return_semester, p_year, p_semester)) THEN
      UPDATE term_results SET reason = 'On leave of absence'
       WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
      CONTINUE;
    END IF;

    v_next_year := CASE WHEN v_prev_sem = '2nd' THEN r.year_level + 1 ELSE r.year_level END;

    IF EXISTS (SELECT 1 FROM student_sections x
                WHERE x.student_id = r.student_id AND x.school_year = p_year AND x.semester = p_semester) THEN
      UPDATE term_results SET placed_at = now()
       WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
      CONTINUE;
    END IF;

    v_sec_id := NULL;
    v_sec_name := NULL;
    SELECT sec.id, sec.name INTO v_sec_id, v_sec_name
      FROM sections sec
     WHERE sec.program_id = r.program_id AND sec.year_level = v_next_year
       AND sec.school_year = p_year AND sec.semester = p_semester
       AND (SELECT count(*) FROM student_sections x WHERE x.section_id = sec.id) < sec.capacity
     ORDER BY (sec.name = r.section_name) DESC, sec.name, sec.id
     LIMIT 1
       FOR UPDATE OF sec;

    IF v_sec_id IS NULL THEN
      UPDATE term_results
         SET result = 'review',
             reason = 'No section with a free seat in ' || r.program_code || ' year ' || v_next_year
       WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
      CONTINUE;
    END IF;

    INSERT INTO student_sections (student_id, section_id) VALUES (r.student_id, v_sec_id);
    UPDATE term_results SET placed_at = now()
     WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
    INSERT INTO notifications (user_id, kind, title, message)
    VALUES (r.user_id, 'section_placed', 'Your section',
            'You are placed in ' || r.program_code || ' ' || v_next_year || v_sec_name || ' for the ' || v_term_text
            || '. Your college is preparing your schedule.');
  END LOOP;

  UPDATE term_closures SET opened_at = now()
   WHERE school_year = v_prev_year AND semester = v_prev_sem;
  PERFORM set_config('app.term_write', 'off', true);
END;
$$;

-- ============================================================
-- 10. Who may call what
--     The helpers and the automatic steps stay internal.
-- ============================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'term_order(text, text)', 'next_regular_term(text, text)', 'leave_return_term(text, text, integer)',
    'leave_covers_term(text, text, text, text, text, text)', 'term_text(text, text)',
    'leave_terms_used(uuid)', 'leave_json(leaves)', 'run_leave_catch_up()',
    'leave_catch_up()', 'record_leave(uuid, text, text, integer, text)', 'decide_leave(uuid, boolean, text)',
    'leave_overview(uuid)', 'leave_requests()', 'students_on_leave()', 'my_leave()', 'my_readmission()'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', f);
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    FOREACH f IN ARRAY ARRAY[
      'term_order(text, text)', 'next_regular_term(text, text)', 'leave_return_term(text, text, integer)',
      'leave_covers_term(text, text, text, text, text, text)', 'term_text(text, text)',
      'leave_terms_used(uuid)', 'leave_json(leaves)', 'run_leave_catch_up()'
    ] LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', f);
    END LOOP;

    FOREACH f IN ARRAY ARRAY[
      'leave_catch_up()', 'record_leave(uuid, text, text, integer, text)', 'decide_leave(uuid, boolean, text)',
      'leave_overview(uuid)', 'leave_requests()', 'students_on_leave()', 'my_leave()', 'my_readmission()'
    ] LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END LOOP;
  END IF;
END $$;
