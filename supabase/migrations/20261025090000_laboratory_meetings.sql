-- ============================================================
-- supabase/migrations/20261025090000_laboratory_meetings.sql
-- Step 8 follow-up: a subject can meet twice (lecture and laboratory).
--
-- Forward-only. The sample PLP Certificate of Registration lists a lecture
-- and a laboratory row for the same subject (for example COMP 104 and
-- COMP 104 Lab), with different rooms, days and times, and units on the
-- lecture row only. section_subjects allowed one row per subject, so the
-- laboratory could not be scheduled.
--
--   - subjects.has_laboratory: the catalog says the subject has a laboratory
--   - section_subjects.meeting: 'lecture' or 'laboratory'; unique per
--     section, subject and meeting
--   - new sections get a lecture row per subject and a laboratory row when
--     the subject has one; the same for subjects added or flagged later
--   - the assessment slip lists both rows and counts units once
--
-- Existing rows become 'lecture'. Nothing changes for subjects without a
-- laboratory.
-- ============================================================

ALTER TABLE subjects ADD COLUMN has_laboratory boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN subjects.has_laboratory IS 'The subject also meets for a laboratory; sections get a second, unit-less row for it.';

ALTER TABLE section_subjects ADD COLUMN meeting text NOT NULL DEFAULT 'lecture'
    CHECK (meeting IN ('lecture','laboratory'));

-- Replace UNIQUE (section_id, subject_id), whatever the database named it.
DO $$
DECLARE
  c text;
BEGIN
  SELECT con.conname INTO c
    FROM pg_constraint con
   WHERE con.conrelid = 'section_subjects'::regclass
     AND con.contype = 'u'
     AND (SELECT array_agg(att.attname::text ORDER BY att.attname)
            FROM unnest(con.conkey) k
            JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k)
         = ARRAY['section_id','subject_id'];
  IF c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE section_subjects DROP CONSTRAINT %I', c);
  END IF;
END $$;
ALTER TABLE section_subjects
    ADD CONSTRAINT section_subjects_unique_meeting UNIQUE (section_id, subject_id, meeting);

-- ============================================================
-- Rows fill themselves (written from 20261025070000_section_scheduling.sql)
-- ============================================================
CREATE OR REPLACE FUNCTION after_section_created() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO section_subjects (section_id, subject_id, meeting)
  SELECT NEW.id, sub.id, m.meeting
    FROM subjects sub
    CROSS JOIN (VALUES ('lecture'), ('laboratory')) m(meeting)
   WHERE sub.program_id = NEW.program_id AND sub.year_level = NEW.year_level
     AND (m.meeting = 'lecture' OR sub.has_laboratory)
   ON CONFLICT (section_id, subject_id, meeting) DO NOTHING;
  PERFORM place_waiting_students(NEW.program_id);
  RETURN NULL;
END;
$$;

-- A subject added to the catalog, or flagged as having a laboratory later,
-- reaches the draft sections of its year level.
CREATE OR REPLACE FUNCTION add_subject_to_draft_sections() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.year_level IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO section_subjects (section_id, subject_id, meeting)
  SELECT sec.id, NEW.id, m.meeting
    FROM sections sec
    CROSS JOIN (VALUES ('lecture'), ('laboratory')) m(meeting)
   WHERE sec.program_id = NEW.program_id AND sec.year_level = NEW.year_level AND sec.schedule_status = 'draft'
     AND (m.meeting = 'lecture' OR NEW.has_laboratory)
   ON CONFLICT (section_id, subject_id, meeting) DO NOTHING;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_subjects_laboratory_added AFTER UPDATE OF has_laboratory ON subjects
    FOR EACH ROW WHEN (NEW.has_laboratory AND NOT OLD.has_laboratory)
    EXECUTE FUNCTION add_subject_to_draft_sections();

-- ============================================================
-- The slip lists every meeting; units count once (the laboratory row shows 0)
-- Written from 20261025080000_assessment_slip.sql.
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
                      'code', sub.code, 'title', sub.title,
                      'meeting', ss.meeting,
                      'units', CASE WHEN ss.meeting = 'laboratory' THEN 0 ELSE sub.units END,
                      'professor', pr.full_name, 'room', r.name,
                      'day', ss.day_of_week,
                      'start', to_char(ss.start_time, 'HH24:MI'),
                      'end', to_char(ss.end_time, 'HH24:MI')
                    ) ORDER BY sub.code, (ss.meeting = 'laboratory')), '[]'::jsonb)
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
