-- Who holds an assessment slip and a COR, section by section, for the current term.
-- Registrar and Admin see every section. The Dean and College Secretary see only
-- the sections of their own college. The caller learns only "issued or not",
-- never the schedule snapshot stored on the slip or the COR.
CREATE OR REPLACE FUNCTION section_document_status()
RETURNS TABLE (
  section_id     uuid,
  section        text,
  student_id     uuid,
  student_number text,
  full_name      text,
  slip_issued    boolean,
  cor_issued     boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin','dean','college_secretary') THEN
    RAISE EXCEPTION 'Only staff can see which students hold a slip or a COR';
  END IF;

  RETURN QUERY
  SELECT sec.id,
         (p.code || ' ' || sec.year_level || sec.name)::text,
         st.id,
         st.student_number::text,
         u.full_name::text,
         EXISTS (SELECT 1 FROM assessment_slips sl
                  WHERE sl.student_id = st.id AND sl.school_year = ss.school_year AND sl.semester = ss.semester),
         EXISTS (SELECT 1 FROM cors c
                  WHERE c.student_id = st.id AND c.school_year = ss.school_year AND c.semester = ss.semester)
    FROM student_sections ss
    JOIN enrollment_term t ON t.school_year = ss.school_year AND t.semester = ss.semester
    JOIN sections sec ON sec.id = ss.section_id
    JOIN programs p ON p.id = sec.program_id
    JOIN students st ON st.id = ss.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
   WHERE a.withdrawn_at IS NULL
     AND (app_role() IN ('registrar','admin') OR p.college_id = app_college_id())
   ORDER BY p.code, sec.year_level, sec.name, st.student_number;
END;
$$;

REVOKE EXECUTE ON FUNCTION section_document_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION section_document_status() TO authenticated;
