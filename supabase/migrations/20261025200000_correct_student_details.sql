-- Name and detail corrections after promotion.
--
-- Until an applicant is promoted, Admissions owns their name and email: a resend
-- refreshes them. After promotion the intake leaves a student alone, and nobody
-- could fix a misspelled name or a wrong email (the Registrar has no write access
-- to users, and Admin had no screen). This adds one function for it.
--
--   correct_student_details(applicant, full_name, email, reason)
--
-- Registrar or Admin only, students only (an applicant is corrected by Admissions
-- and a resend), and a reason is required. It changes users.full_name and
-- users.email in one transaction, writes the reason to the audit log (the users
-- trigger records the before and after), and notifies the student.
--
-- The name is read live by the assessment slip, the COR, class lists and every
-- search, so nothing else needs fixing. A slip or COR already printed on paper
-- is not changed. The student number, program, section and admission type are
-- not touched: they drive the visit, the seat and the checklist.
--
-- The sign-in email (auth.users) is changed by the server action before it calls
-- this, the same way the Admissions intake does it.

CREATE OR REPLACE FUNCTION correct_student_details(
  p_applicant uuid,
  p_full_name text,
  p_email     text,
  p_reason    text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_name    text := btrim(regexp_replace(coalesce(p_full_name, ''), '\s+', ' ', 'g'));
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_app     applicants%ROWTYPE;
  v_user    users%ROWTYPE;
  v_changed text[] := ARRAY[]::text[];
  v_message text;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can correct a student''s details';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  IF length(v_name) < 2 OR length(v_name) > 150 THEN
    RAISE EXCEPTION 'Enter the full name';
  END IF;
  IF v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN
    RAISE EXCEPTION 'Enter a valid email address';
  END IF;

  -- Two people correcting the same student queue here.
  SELECT * INTO v_app FROM applicants WHERE id = p_applicant FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE applicant_id = v_app.id) THEN
    RAISE EXCEPTION 'This person is not a student yet. Admissions sends corrections until documents are received';
  END IF;
  IF v_app.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = v_app.user_id FOR UPDATE;

  IF v_user.full_name IS DISTINCT FROM v_name THEN
    v_changed := v_changed || 'name';
  END IF;
  IF lower(v_user.email::text) IS DISTINCT FROM v_email THEN
    IF EXISTS (SELECT 1 FROM users WHERE email = v_email AND id <> v_user.id) THEN
      RAISE EXCEPTION 'This email already belongs to another account';
    END IF;
    v_changed := v_changed || 'email';
  END IF;

  IF cardinality(v_changed) = 0 THEN
    RAISE EXCEPTION 'Nothing was changed';
  END IF;

  PERFORM set_config('app.audit_reason', v_reason, true);

  UPDATE users SET full_name = v_name, email = v_email WHERE id = v_user.id;

  v_message := 'The Registrar corrected your ' || array_to_string(v_changed, ' and ') || '.';
  IF 'name' = ANY (v_changed) THEN
    v_message := v_message || ' Your name is now ' || v_name || '.';
  END IF;
  IF 'email' = ANY (v_changed) THEN
    v_message := v_message || ' Your sign-in email is now ' || v_email || '.';
  END IF;
  v_message := v_message || ' Reason: ' || v_reason;

  INSERT INTO notifications (user_id, kind, title, message, email_status)
  VALUES (v_user.id, 'details_corrected', 'Your details were corrected', v_message, 'pending');

  PERFORM set_config('app.audit_reason', '', true);
  RETURN v_user.id;
END;
$$;

REVOKE ALL ON FUNCTION correct_student_details(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION correct_student_details(uuid, text, text, text) TO authenticated;
