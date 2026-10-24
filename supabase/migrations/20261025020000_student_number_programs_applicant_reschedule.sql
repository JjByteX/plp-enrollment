-- Forward-only follow-up to 20261025000000_init.sql (never edit a merged migration).
-- 1. Student number format YY-00001 (year prefix, 5 digit counter that restarts each year).
-- 2. Seed the 7 colleges and the 13 Admissions programs.
-- 3. Let Applicants request a reschedule, not only Students.

-- ============================================================
-- 1. Student number: YY-NNNNN, for example 24-00669.
--    YY is the last two digits of the year the number is assigned
--    (Manila time). NNNNN counts up from 00001 each year and is handed
--    out under a row lock, so two numbers are never the same.
-- ============================================================
CREATE TABLE student_number_counters (
    year         smallint PRIMARY KEY,
    last_number  integer NOT NULL
);
ALTER TABLE student_number_counters ENABLE ROW LEVEL SECURITY; -- no policies: only the function below touches it

CREATE OR REPLACE FUNCTION generate_student_number() RETURNS varchar
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_year smallint := extract(year FROM (now() AT TIME ZONE 'Asia/Manila'))::smallint;
  v_next integer;
BEGIN
  INSERT INTO student_number_counters (year, last_number) VALUES (v_year, 1)
  ON CONFLICT (year) DO UPDATE SET last_number = student_number_counters.last_number + 1
  RETURNING last_number INTO v_next;

  IF v_next > 99999 THEN
    RAISE EXCEPTION 'Student numbers for % are used up (99999 per year)', v_year;
  END IF;

  RETURN lpad((v_year % 100)::text, 2, '0') || '-' || lpad(v_next::text, 5, '0');
END;
$$;

-- Only the promotion trigger may call it. Calling it directly would burn numbers.
REVOKE EXECUTE ON FUNCTION generate_student_number() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION generate_student_number() FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION generate_student_number() FROM authenticated;
  END IF;
END $$;

-- ============================================================
-- 2. Colleges and programs. Codes are the text in brackets in
--    Admissions' official course names (PLP_COURSES in its config/app.php).
-- ============================================================
INSERT INTO colleges (code, name) VALUES
    ('CCS', 'College of Computer Studies'),
    ('CON', 'College of Nursing'),
    ('CBA', 'College of Business and Accountancy'),
    ('COE', 'College of Education'),
    ('CAS', 'College of Arts and Sciences'),
    ('CEN', 'College of Engineering'),
    ('HM',  'College of Hospitality Management')
ON CONFLICT (code) DO NOTHING;

INSERT INTO programs (code, name, college_id)
SELECT v.code, v.name, c.id
FROM (VALUES
    ('BSA',       'BS Accountancy',                                                    'CBA'),
    ('BSBA',      'BS Business Administration major in Marketing Management',          'CBA'),
    ('BSENT',     'BS Entrepreneurship',                                               'CBA'),
    ('BSHM',      'BS Hospitality Management',                                         'HM'),
    ('BEED',      'Bachelor of Elementary Education',                                  'COE'),
    ('BSED-ENG',  'Bachelor of Secondary Education Major in English',                  'COE'),
    ('BSED-FIL',  'Bachelor of Secondary Education Major in Filipino',                 'COE'),
    ('BSED-MATH', 'Bachelor of Secondary Education Major in Mathematics',              'COE'),
    ('AB Psych',  'AB Psychology',                                                     'CAS'),
    ('BSCS',      'BS Computer Science',                                               'CCS'),
    ('BSIT',      'BS Information Technology',                                         'CCS'),
    ('BSECE',     'BS Electronics Engineering',                                        'CEN'),
    ('BSN',       'BS Nursing',                                                        'CON')
) AS v(code, name, college_code)
JOIN colleges c ON c.code = v.college_code
ON CONFLICT (code) DO NOTHING;

-- ============================================================
-- 3. Applicants may request a reschedule for their own booking, as
--    Students already can. Same Registrar approval path.
-- ============================================================
DROP POLICY IF EXISTS requests_student_insert ON reschedule_requests;
CREATE POLICY requests_applicant_student_insert ON reschedule_requests FOR INSERT TO authenticated
    WITH CHECK (
      app_role() IN ('applicant','student')
      AND requested_by = current_actor_id()
      AND booking_id IN (SELECT vb.id FROM visit_bookings vb WHERE vb.applicant_id = my_applicant_id())
    );
