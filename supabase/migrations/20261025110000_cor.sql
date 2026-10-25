-- ============================================================
-- supabase/migrations/20261025110000_cor.sql
-- Step 11: Certificate of Registration (COR).
--
-- Forward-only. The cors table and its gate (slip issued, payment cleared
-- when the slip says it is required, Registrar or Admin only) are already in
-- 20261025000000_init.sql. A row in cors means the student is enrolled.
-- This adds:
--   - enrollment_term: the school year and semester, set by Admin (one row)
--   - cors.school_year and cors.semester, copied when the COR is issued so a
--     later term change never alters an old COR
--   - enforce_cor_gate: now also fills the term, and refuses when none is set
--   - issue_cor: one student, with the notification, in one transaction
--   - issue_all_ready_cors: every student whose slip is issued and payment is
--     cleared or not required, no COR yet
--   - certificate_of_registration: what the COR shows
--
-- Admin sets the term by SQL until the content editors of step 15:
--   INSERT INTO enrollment_term (school_year, semester) VALUES ('2026-2027','1st');
--   UPDATE enrollment_term SET school_year = '2026-2027', semester = '2nd';
--
-- cors had no writer before this step, so the NOT NULL columns assume the
-- table is empty (same stance as sections.capacity in step 8).
-- ============================================================

-- ============================================================
-- 1. The current term (one row, Admin only)
-- ============================================================
CREATE TABLE enrollment_term (
    id           boolean PRIMARY KEY DEFAULT true CHECK (id),
    school_year  text NOT NULL CHECK (
        CASE WHEN school_year ~ '^[0-9]{4}-[0-9]{4}$'
             THEN right(school_year, 4)::int = left(school_year, 4)::int + 1
             ELSE false END),
    semester     text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    updated_by   uuid NULL REFERENCES users (id),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE enrollment_term IS 'The school year and semester an issued COR is stamped with. One row, Admin only, audit-logged.';

-- Same stamp as the payment toggle: updated_by and updated_at, nothing else.
CREATE TRIGGER trg_enrollment_term_stamp BEFORE INSERT OR UPDATE ON enrollment_term
    FOR EACH ROW EXECUTE FUNCTION stamp_payment_setting();
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON enrollment_term
    FOR EACH ROW EXECUTE FUNCTION log_audit();

ALTER TABLE enrollment_term ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_all ON enrollment_term FOR ALL TO authenticated
    USING (app_role() = 'admin') WITH CHECK (app_role() = 'admin');

-- ============================================================
-- 2. The term on each COR
-- ============================================================
ALTER TABLE cors ADD COLUMN school_year text NOT NULL CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$');
ALTER TABLE cors ADD COLUMN semester text NOT NULL CHECK (semester IN ('1st','2nd','summer'));

-- Written from 20261025000000_init.sql: the same rules, plus the term.
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
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. Issue one COR
-- ============================================================
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

  IF EXISTS (SELECT 1 FROM cors WHERE student_id = p_student) THEN
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

-- ============================================================
-- 4. Issue every COR that is ready
--    Ready = slip issued, payment cleared or not required, no COR yet.
--    Lowest student number first. Returns how many were issued.
-- ============================================================
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
     WHERE NOT EXISTS (SELECT 1 FROM cors c WHERE c.student_id = st.id)
       AND (NOT sl.payment_required
            OR EXISTS (SELECT 1 FROM payments pay WHERE pay.student_id = st.id AND pay.status = 'cleared'))
     ORDER BY st.student_number
  LOOP
    PERFORM issue_cor(r.id);
    issued := issued + 1;
  END LOOP;
END;
$$;

-- ============================================================
-- 5. What the COR shows
--    The student it belongs to, the Registrar and Admin may read it; anyone
--    else is refused. Null when no COR was issued yet. The schedule is the
--    same list the assessment slip shows (units counted once). The payment
--    amounts are there only when payment was required and cleared; there is
--    no fee schedule, so no tuition, miscellaneous or laboratory lines.
-- ============================================================
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
           'subjects', assessment_slip(p_student)->'subjects'
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
-- 6. Who may call them. The functions also check the role themselves.
-- ============================================================
REVOKE EXECUTE ON FUNCTION issue_cor(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION issue_all_ready_cors() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION certificate_of_registration(uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION issue_cor(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION issue_all_ready_cors() FROM anon;
    REVOKE EXECUTE ON FUNCTION certificate_of_registration(uuid) FROM anon;
  END IF;
END $$;
