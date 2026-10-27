-- ============================================================
-- supabase/migrations/20261026050000_close_term.sql
-- Step 21: close term, review list and automatic promotion.
--
-- Forward-only. Written from docs/step-18-returning-students-plan.md, decisions J, M, N, O, P and T.
--
--   - term_closures: one row per closed term. A term is closed once, by the Registrar or
--     Admin, and only while every section subject that has students has Dean-approved
--     grades. opened_at is set when the next term opens and its students are promoted.
--   - term_results: what closing decided for each enrolled, non-withdrawn student of the
--     term: promote (every subject of the section passed), review (anything else, with the
--     reason in words) or completed (passed the last semester of the last year).
--     A student with no enrollment in the term, and a withdrawn student, get no row.
--   - open_term: runs by itself when Admin changes the current term (trigger on
--     enrollment_term). If the term before it was closed and not opened yet, it creates the
--     new term's sections by copying the closed term's (same names and capacities; the
--     subjects fill in from the catalog; no professors, rooms or times) and seats every
--     student marked promote in the right section with a free seat, with a notification.
--     A student who cannot be seated moves to the review list with that reason.
--   - review_students, completed_students, term_close_status, my_needs_advising: reads.
--
-- Next regular term: 1st goes to 2nd of the same year, 2nd goes to 1st of the next school year,
-- and a summer term in between is skipped. Summer is never part of automatic promotion: closing
-- a summer term records the closure and decides nothing for anyone.
--
-- Writes to the two tables go only through the functions below. A trigger refuses any other
-- write, Admin included. Everything is audited like the other tables.
-- ============================================================

-- ============================================================
-- 1. Tables
-- ============================================================
CREATE TABLE term_closures (
    school_year  text NOT NULL CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
    semester     text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    closed_by    uuid NULL REFERENCES users (id),
    closed_at    timestamptz NOT NULL DEFAULT now(),
    opened_at    timestamptz NULL,
    PRIMARY KEY (school_year, semester)
);
COMMENT ON TABLE term_closures IS 'A closed term. opened_at is set once the next regular term has opened and its students were promoted.';

CREATE TABLE term_results (
    school_year  text NOT NULL,
    semester     text NOT NULL,
    student_id   uuid NOT NULL REFERENCES students (id),
    program_id   uuid NOT NULL REFERENCES programs (id),
    year_level   smallint NOT NULL,
    section_name varchar(50) NOT NULL,
    result       text NOT NULL CHECK (result IN ('promote','review','completed')),
    reason       text NULL,
    placed_at    timestamptz NULL,
    PRIMARY KEY (school_year, semester, student_id),
    FOREIGN KEY (school_year, semester) REFERENCES term_closures (school_year, semester)
);
CREATE INDEX idx_term_results_student ON term_results (student_id);
COMMENT ON TABLE term_results IS 'What closing a term decided for each enrolled student: promote, review (with the reason) or completed.';
COMMENT ON COLUMN term_results.placed_at IS 'When a promoted student was seated in the next term''s section.';

-- ============================================================
-- 2. Direct writes are refused; the functions below turn the switch on
-- ============================================================
CREATE OR REPLACE FUNCTION refuse_direct_term_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.term_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Term results change only through closing a term';
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
  FOREACH t IN ARRAY ARRAY['term_closures','term_results'] LOOP
    EXECUTE format('CREATE TRIGGER trg_term_write_guard BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION refuse_direct_term_write()', t);
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION log_audit()', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY admin_all ON %I FOR ALL TO authenticated USING (app_role() = ''admin'') WITH CHECK (app_role() = ''admin'')', t);
  END LOOP;
END $$;

-- audit_log.record_id comes from the row's "id" key; these two tables have none, so the
-- audit row keeps the whole old and new row and a null record id, like enrollment_term's id.

-- ============================================================
-- 3. Small helpers (internal)
-- ============================================================
-- The regular term before a term: 2nd goes back to 1st, 1st goes back to the 2nd of the
-- school year before. A summer term has none.
CREATE OR REPLACE FUNCTION previous_regular_term(p_year text, p_semester text)
RETURNS TABLE (prev_year text, prev_semester text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester
           WHEN '2nd' THEN p_year
           ELSE (left(p_year, 4)::integer - 1)::text || '-' || left(p_year, 4)
         END,
         CASE p_semester WHEN '2nd' THEN '1st' ELSE '2nd' END
   WHERE p_semester IN ('1st','2nd') AND p_year ~ '^[0-9]{4}-[0-9]{4}$'
$$;

-- Has the student an enrollment in a term after the given one? (Summer comes after 2nd.)
CREATE OR REPLACE FUNCTION has_enrollment_after(p_student uuid, p_year text, p_semester text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM student_sections ss
     WHERE ss.student_id = p_student
       AND (ss.school_year > p_year
            OR (ss.school_year = p_year AND semester_rank(ss.semester) > semester_rank(p_semester))))
$$;

-- The section subjects of the current term that still wait for Dean-approved grades. Only
-- sections that have students count: a section nobody is enrolled in has nothing to grade.
CREATE OR REPLACE FUNCTION term_missing_sheets() RETURNS TABLE (m_label text, m_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (p.code || ' ' || sec.year_level || sec.name)::text, sub.code::text
    FROM enrollment_term t
    JOIN sections sec ON sec.school_year = t.school_year AND sec.semester = t.semester
    JOIN programs p ON p.id = sec.program_id
    JOIN (SELECT DISTINCT section_id, subject_id FROM section_subjects) x ON x.section_id = sec.id
    JOIN subjects sub ON sub.id = x.subject_id
   WHERE EXISTS (SELECT 1 FROM student_sections ss WHERE ss.section_id = sec.id)
     AND NOT EXISTS (SELECT 1 FROM grade_sheets gs
                      WHERE gs.section_id = sec.id AND gs.subject_id = sub.id AND gs.status = 'approved')
   ORDER BY 1, 2
$$;

-- ============================================================
-- 4. Reading
-- ============================================================
-- The Close term control: the current term, whether it is closed, and what is still missing.
CREATE OR REPLACE FUNCTION term_close_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_term    enrollment_term%ROWTYPE;
  v_closed  boolean;
  v_total   integer;
  v_missing jsonb;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can see the term status';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('term', NULL, 'closed', false, 'enrolled', 0, 'missing', '[]'::jsonb, 'missingTotal', 0);
  END IF;

  v_closed := EXISTS (SELECT 1 FROM term_closures c
                       WHERE c.school_year = v_term.school_year AND c.semester = v_term.semester);
  SELECT count(*) INTO v_total FROM term_missing_sheets();
  SELECT coalesce(jsonb_agg(jsonb_build_object('label', q.m_label, 'code', q.m_code) ORDER BY q.m_label, q.m_code), '[]'::jsonb)
    INTO v_missing
    FROM (SELECT m.m_label, m.m_code FROM term_missing_sheets() m ORDER BY m.m_label, m.m_code LIMIT 5) q;

  RETURN jsonb_build_object(
    'term', jsonb_build_object('schoolYear', v_term.school_year, 'semester', v_term.semester),
    'closed', v_closed,
    'enrolled', (SELECT count(*) FROM student_sections ss
                  WHERE ss.school_year = v_term.school_year AND ss.semester = v_term.semester),
    'missing', v_missing,
    'missingTotal', v_total);
END;
$$;

-- Students who need a load built by hand: the review result of a closed term, with no
-- enrollment after it yet. The Dean and the Secretary see their own college, Admin all.
CREATE OR REPLACE FUNCTION review_students() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read the review list';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'studentId', st.id,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'yearLevel', tr.year_level,
             'schoolYear', tr.school_year,
             'semester', tr.semester,
             'reason', coalesce(tr.reason, '')
           ) ORDER BY p.code, st.student_number)
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = tr.program_id
     WHERE tr.result = 'review'
       AND a.withdrawn_at IS NULL
       AND NOT has_enrollment_after(tr.student_id, tr.school_year, tr.semester)
       AND (v_role = 'admin' OR program_in_my_college(tr.program_id))
  ), '[]'::jsonb);
END;
$$;

-- Students who passed the last semester of the last year of their program.
CREATE OR REPLACE FUNCTION completed_students() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can read the completed students';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'studentId', st.id,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'schoolYear', tr.school_year,
             'semester', tr.semester
           ) ORDER BY tr.school_year DESC, semester_rank(tr.semester) DESC, p.code, st.student_number)
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = tr.program_id
     WHERE tr.result = 'completed' AND a.withdrawn_at IS NULL
  ), '[]'::jsonb);
END;
$$;

-- True for a student on the review list, so the next step card can send them to their college.
-- No grade is read out (decision S).
CREATE OR REPLACE FUNCTION my_needs_advising() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
     WHERE tr.student_id = my_student_id()
       AND tr.result = 'review'
       AND a.withdrawn_at IS NULL
       AND NOT has_enrollment_after(tr.student_id, tr.school_year, tr.semester))
$$;

-- ============================================================
-- 5. Closing the current term
-- ============================================================
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

  -- Two people closing at once, or Admin changing the term, queue here.
  SELECT * INTO v_term FROM enrollment_term FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF EXISTS (SELECT 1 FROM term_closures c
              WHERE c.school_year = v_term.school_year AND c.semester = v_term.semester) THEN
    RAISE EXCEPTION 'This term is already closed';
  END IF;

  -- An incomplete past its window becomes a failed 5.0 before anyone is judged on it.
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

  -- Summer is never part of automatic promotion: nothing is decided for anyone.
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
      -- Every subject of the section counts. Anything that is not an approved pass is named.
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
        FROM (SELECT DISTINCT x.subject_id FROM section_subjects x WHERE x.section_id = r.section_id) d
        JOIN subjects s ON s.id = d.subject_id
        LEFT JOIN grades g ON g.student_id = r.student_id AND g.section_id = r.section_id AND g.subject_id = s.id
                          AND EXISTS (SELECT 1 FROM grade_sheets gs WHERE gs.id = g.sheet_id AND gs.status = 'approved');

      -- The last year of a program is the highest year level that has subjects, and its last
      -- semester is the 2nd when that year has a 2nd semester subject, else the 1st.
      SELECT max(sub.year_level) INTO v_last_year FROM subjects sub WHERE sub.program_id = r.program_id;
      v_last_sem := CASE WHEN EXISTS (SELECT 1 FROM subjects sub
                                       WHERE sub.program_id = r.program_id AND sub.year_level = v_last_year
                                         AND sub.semester = '2nd')
                         THEN '2nd' ELSE '1st' END;

      IF v_counted = 0 THEN
        v_result := 'review';
        v_reason := 'The section has no subjects';
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
-- 6. Opening the next term
--    Runs from the trigger below when Admin changes the current term. Does nothing unless the
--    regular term before the new one is closed and has not been opened yet.
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

  -- The new term's sections. 1st to 2nd: every section of the closed term is copied. 2nd to 1st:
  -- the year 1 sections are copied for the new students, and every other section is copied one year
  -- level up (same name and capacity) while that year level is still in the program.
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

  -- Seat every promoted student: the next year level when the closed term was a 2nd semester,
  -- else the same one. The section of the same name first, then the first with a free seat.
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

CREATE OR REPLACE FUNCTION after_term_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM open_term(NEW.school_year, NEW.semester);
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_enrollment_term_open AFTER UPDATE ON enrollment_term
    FOR EACH ROW
    WHEN (OLD.school_year IS DISTINCT FROM NEW.school_year OR OLD.semester IS DISTINCT FROM NEW.semester)
    EXECUTE FUNCTION after_term_changed();

-- ============================================================
-- 7. Who may call what
--    The helpers and open_term stay internal.
-- ============================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'previous_regular_term(text, text)', 'has_enrollment_after(uuid, text, text)', 'term_missing_sheets()',
    'open_term(text, text)',
    'term_close_status()', 'review_students()', 'completed_students()', 'my_needs_advising()', 'close_term()'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', f);
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    FOREACH f IN ARRAY ARRAY[
      'previous_regular_term(text, text)', 'has_enrollment_after(uuid, text, text)', 'term_missing_sheets()',
      'open_term(text, text)'
    ] LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', f);
    END LOOP;

    FOREACH f IN ARRAY ARRAY[
      'term_close_status()', 'review_students()', 'completed_students()', 'my_needs_advising()', 'close_term()'
    ] LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END LOOP;
  END IF;
END $$;
