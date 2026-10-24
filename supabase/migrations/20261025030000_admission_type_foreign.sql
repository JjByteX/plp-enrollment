-- Forward-only follow-up (never edit a merged migration).
-- Admissions has a third applicant type, foreign. Keep it instead of
-- folding it into "new", so the Registrar can see it and ask for the
-- extra documents foreign students need.
-- Replaces the admission_type check on admissions_intake_log and applicants.
-- Safe to run twice.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname, c.conrelid::regclass AS tbl
    FROM pg_constraint c
    WHERE c.contype = 'c'
      AND c.conrelid IN ('public.admissions_intake_log'::regclass, 'public.applicants'::regclass)
      AND pg_get_constraintdef(c.oid) LIKE '%admission_type%'
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
  END LOOP;
END $$;

ALTER TABLE admissions_intake_log
  ADD CONSTRAINT admissions_intake_log_admission_type_check
  CHECK (admission_type IN ('new','transferee','foreign'));

ALTER TABLE applicants
  ADD CONSTRAINT applicants_admission_type_check
  CHECK (admission_type IN ('new','transferee','foreign'));
