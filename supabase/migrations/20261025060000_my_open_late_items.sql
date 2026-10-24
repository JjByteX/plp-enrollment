-- Forward-only follow-up (never edit a merged migration).
-- Step 7, "Your next step" card for a Student. A Student cannot read the
-- documents table (Registrar and Admin only), so this function answers one
-- question for the signed-in Student and nobody else: which late items
-- (Form 137) are still open. It returns labels only, never notes or dates.
-- Returns an empty list for anyone who is not a student.

CREATE OR REPLACE FUNCTION my_open_late_items() RETURNS text[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(array_agg(r.label ORDER BY r.sort_order), ARRAY[]::text[])
  FROM students s
  JOIN applicants a ON a.id = s.applicant_id
  JOIN document_requirements r
    ON r.active AND NOT r.required AND r.doc_type <> 'other' AND a.admission_type = ANY (r.applies_to)
  WHERE s.id = my_student_id()
    AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.applicant_id = a.id AND d.doc_type = r.doc_type)
$$;

REVOKE EXECUTE ON FUNCTION my_open_late_items() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION my_open_late_items() FROM anon;
  END IF;
END $$;
