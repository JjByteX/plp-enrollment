-- ============================================================
-- supabase/migrations/20261025080000_assessment_slip.sql
-- Step 9: assessment slip.
--
-- Forward-only. The table, its gate (approved schedule, Registrar only,
-- payment snapshot) and the pending payment it opens are already in
-- 20261025000000_init.sql. This adds:
--   - issue_assessment_slip: one student, with the notification, in one transaction
--   - issue_all_ready_slips: every student whose section is approved and has no slip
--   - assessment_slip: what the slip shows, for the student it belongs to or the Registrar
--
-- The slip is the light version: student number, name, program, section,
-- and the subjects with professor, room, day and time, plus whether payment
-- is required. A student cannot read subjects, rooms or professors with
-- their own session, so the content comes from a function.
-- ============================================================

-- ============================================================
-- 1. Issue one slip
-- ============================================================
CREATE OR REPLACE FUNCTION issue_assessment_slip(p_student uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user     uuid;
  v_slip     uuid;
  v_required boolean;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue assessment slips';
  END IF;

  -- Two Registrars on the same student queue here; the second one then
  -- finds the slip and stops.
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student
     FOR UPDATE OF st;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;

  IF EXISTS (SELECT 1 FROM assessment_slips WHERE student_id = p_student) THEN
    RAISE EXCEPTION 'The assessment slip was already issued';
  END IF;

  -- The gate trigger refuses unless the schedule is approved, and sets
  -- payment_required (program toggle snapshot), issued_by and issued_at.
  INSERT INTO assessment_slips (student_id, payment_required, issued_by)
  VALUES (p_student, false, current_actor_id())
  RETURNING id, payment_required INTO v_slip, v_required;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (
    v_user, 'slip_issued', 'Your assessment slip',
    CASE WHEN v_required
      THEN 'Your assessment slip is ready. Next, Finance clears your payment, then the Registrar issues your COR.'
      ELSE 'Your assessment slip is ready. Next, the Registrar issues your COR.'
    END
  );

  RETURN v_slip;
END;
$$;

-- ============================================================
-- 2. Issue every slip that is ready
--    Ready = placed in a section whose schedule is approved, no slip yet.
--    Oldest student number first. Returns how many were issued.
-- ============================================================
CREATE OR REPLACE FUNCTION issue_all_ready_slips(OUT issued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue assessment slips';
  END IF;

  issued := 0;
  FOR r IN
    SELECT st.id
      FROM students st
      JOIN student_sections ss ON ss.student_id = st.id
      JOIN sections sec ON sec.id = ss.section_id
     WHERE sec.schedule_status = 'approved'
       AND NOT EXISTS (SELECT 1 FROM assessment_slips sl WHERE sl.student_id = st.id)
     ORDER BY st.student_number
  LOOP
    PERFORM issue_assessment_slip(r.id);
    issued := issued + 1;
  END LOOP;
END;
$$;

-- ============================================================
-- 3. What the slip shows
--    The student it belongs to, the Registrar and Admin may read it;
--    anyone else is refused. Null when no slip was issued yet.
-- ============================================================
CREATE OR REPLACE FUNCTION assessment_slip(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF app_role() IS NULL
     OR (app_role() NOT IN ('registrar','admin') AND p_student IS DISTINCT FROM my_student_id()) THEN
    RAISE EXCEPTION 'You can only view your own assessment slip';
  END IF;

  SELECT jsonb_build_object(
           'studentNumber', st.student_number,
           'fullName', u.full_name,
           'programCode', p.code,
           'programName', p.name,
           'section', p.code || ' Year ' || sec.year_level || ' - ' || sec.name,
           'issuedAt', sl.issued_at,
           'paymentRequired', sl.payment_required,
           'subjects', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
                      'code', sub.code, 'title', sub.title, 'units', sub.units,
                      'professor', pr.full_name, 'room', r.name,
                      'day', ss.day_of_week,
                      'start', to_char(ss.start_time, 'HH24:MI'),
                      'end', to_char(ss.end_time, 'HH24:MI')
                    ) ORDER BY sub.code), '[]'::jsonb)
               FROM section_subjects ss
               JOIN subjects sub ON sub.id = ss.subject_id
               LEFT JOIN users pr ON pr.id = ss.professor_id
               LEFT JOIN rooms r ON r.id = ss.room_id
              WHERE ss.section_id = sec.id)
         )
    INTO v_result
    FROM assessment_slips sl
    JOIN students st ON st.id = sl.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN student_sections sts ON sts.student_id = st.id
    JOIN sections sec ON sec.id = sts.section_id
   WHERE sl.student_id = p_student;

  RETURN v_result;
END;
$$;

-- ============================================================
-- 4. Who may call them. The functions also check the role themselves.
-- ============================================================
REVOKE EXECUTE ON FUNCTION issue_assessment_slip(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION issue_all_ready_slips() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION assessment_slip(uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION issue_assessment_slip(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION issue_all_ready_slips() FROM anon;
    REVOKE EXECUTE ON FUNCTION assessment_slip(uuid) FROM anon;
  END IF;
END $$;
