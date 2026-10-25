-- ============================================================
-- supabase/migrations/20261025070000_section_scheduling.sql
-- Step 8: section, professor and room scheduling.
--
-- Forward-only. Builds on the section tables in 20261025000000_init.sql
-- (sections, section_subjects, student_sections, the schedule gates).
--
-- Decisions (open-questions.md #14 and #15, decision-log.md #18 and #19):
--   - A Dean or Registrar rejection sends the schedule back to draft with
--     a required reason. The Secretary fixes it and submits again.
--   - Students are placed into sections automatically. The Secretary or
--     Dean can move a student at any time (until the slip is issued).
--
-- sections.capacity is NOT NULL with no default. The sections table has
-- no rows today (nothing wrote to it before this step); if production
-- has rows, this migration stops there and nothing is applied.
-- ============================================================

-- ============================================================
-- 1. Columns
-- ============================================================
ALTER TABLE sections ADD COLUMN capacity integer NOT NULL CHECK (capacity > 0);
ALTER TABLE sections ADD COLUMN rejected_reason text NULL;
ALTER TABLE sections ADD COLUMN rejected_by uuid NULL REFERENCES users (id);
ALTER TABLE sections ADD COLUMN rejected_at timestamptz NULL;
COMMENT ON COLUMN sections.capacity IS 'Seats for automatic placement. A manual move by the Secretary or Dean may go over it.';
COMMENT ON COLUMN sections.rejected_reason IS 'Why the Dean or Registrar sent the schedule back to draft. Cleared when it is submitted again.';

-- ============================================================
-- 2. The schedule gates, replaced (decision-log.md #4 and #18)
--    Written from enforce_section_gates() in the init migration.
--    New: pending_dean -> draft (Dean) and dean_signed -> draft
--    (Registrar), both with a required reason; a schedule cannot be
--    submitted while a subject has no professor, room or time; program
--    and year level of a section never change; capacity is editable.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_section_gates() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_actor   uuid := current_actor_id();
  v_college uuid;
  v_reason  text := nullif(trim(coalesce(current_setting('app.audit_reason', true), '')), '');
  v_rows    integer;
  v_open    integer;
BEGIN
  IF NEW.program_id IS DISTINCT FROM OLD.program_id OR NEW.year_level IS DISTINCT FROM OLD.year_level THEN
    RAISE EXCEPTION 'The program and year level of a section cannot be changed';
  END IF;

  IF NEW.schedule_status = OLD.schedule_status THEN
    -- the sign-off and rejection columns are only ever set by a status change
    NEW.prepared_by := OLD.prepared_by;
    NEW.dean_signed_by := OLD.dean_signed_by;
    NEW.dean_signed_at := OLD.dean_signed_at;
    NEW.approved_by := OLD.approved_by;
    NEW.approved_at := OLD.approved_at;
    NEW.rejected_reason := OLD.rejected_reason;
    NEW.rejected_by := OLD.rejected_by;
    NEW.rejected_at := OLD.rejected_at;
    IF v_role = 'registrar' AND (NEW.name, NEW.capacity) IS DISTINCT FROM (OLD.name, OLD.capacity) THEN
      RAISE EXCEPTION 'The Registrar cannot edit section details';
    END IF;
    RETURN NEW;
  END IF;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'An identified user is required to change a schedule status';
  END IF;
  SELECT college_id INTO v_college FROM programs WHERE id = NEW.program_id;

  IF OLD.schedule_status = 'draft' AND NEW.schedule_status = 'pending_dean' THEN
    IF v_role NOT IN ('college_secretary','dean','admin')
       OR (v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college) THEN
      RAISE EXCEPTION 'Only this college''s Secretary or Dean can submit a schedule for sign-off';
    END IF;
    SELECT count(*)::integer,
           count(*) FILTER (WHERE professor_id IS NULL OR room_id IS NULL OR day_of_week IS NULL)::integer
      INTO v_rows, v_open
      FROM section_subjects WHERE section_id = NEW.id;
    IF v_rows = 0 THEN
      RAISE EXCEPTION 'This section has no subjects yet, so there is nothing to sign off';
    END IF;
    IF v_open > 0 THEN
      RAISE EXCEPTION '% of % subjects still need a professor, room and time', v_open, v_rows;
    END IF;
    NEW.prepared_by := v_actor;
    NEW.rejected_reason := NULL;
    NEW.rejected_by := NULL;
    NEW.rejected_at := NULL;
  ELSIF OLD.schedule_status = 'pending_dean' AND NEW.schedule_status = 'dean_signed' THEN
    IF v_role NOT IN ('dean','admin')
       OR (v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college) THEN
      RAISE EXCEPTION 'Only this college''s Dean can sign off professor loading';
    END IF;
    NEW.dean_signed_by := v_actor;
    NEW.dean_signed_at := now();
  ELSIF OLD.schedule_status = 'dean_signed' AND NEW.schedule_status = 'approved' THEN
    IF v_role NOT IN ('registrar','admin') THEN
      RAISE EXCEPTION 'Only the Registrar can approve a schedule';
    END IF;
    NEW.approved_by := v_actor;
    NEW.approved_at := now();
  ELSIF OLD.schedule_status = 'pending_dean' AND NEW.schedule_status = 'draft' THEN
    IF v_role NOT IN ('dean','admin')
       OR (v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college) THEN
      RAISE EXCEPTION 'Only this college''s Dean can reject a schedule waiting for sign-off';
    END IF;
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'A reason is required to reject a schedule';
    END IF;
    NEW.rejected_reason := v_reason;
    NEW.rejected_by := v_actor;
    NEW.rejected_at := now();
  ELSIF OLD.schedule_status = 'dean_signed' AND NEW.schedule_status = 'draft' THEN
    IF v_role NOT IN ('registrar','admin') THEN
      RAISE EXCEPTION 'Only the Registrar can reject a schedule signed by the Dean';
    END IF;
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'A reason is required to reject a schedule';
    END IF;
    NEW.rejected_reason := v_reason;
    NEW.rejected_by := v_actor;
    NEW.rejected_at := now();
    -- the Dean signs again after the Secretary fixes it
    NEW.dean_signed_by := NULL;
    NEW.dean_signed_at := NULL;
  ELSE
    RAISE EXCEPTION 'Invalid schedule status change: % to %', OLD.schedule_status, NEW.schedule_status;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. Professor loading rules, replaced
--    Written from enforce_section_subject_rules() in the init migration.
--    New: the subject must belong to the section's program, and a room
--    tied to a college must be that section's college.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_section_subject_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_section uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.section_id ELSE NEW.section_id END;
  v_status  text;
  v_program uuid;
  v_college uuid;
BEGIN
  SELECT s.schedule_status, s.program_id, p.college_id
    INTO v_status, v_program, v_college
    FROM sections s JOIN programs p ON p.id = s.program_id
   WHERE s.id = v_section;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'The schedule is already submitted; professor loading is locked';
  END IF;
  IF TG_OP <> 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM subjects WHERE id = NEW.subject_id AND program_id = v_program) THEN
      RAISE EXCEPTION 'That subject does not belong to this section''s program';
    END IF;
    IF NEW.professor_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.professor_id AND role = 'professor' AND is_active) THEN
      RAISE EXCEPTION 'Assigned user is not an active Professor';
    END IF;
    IF NEW.room_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM rooms WHERE id = NEW.room_id AND (college_id IS NULL OR college_id = v_college)) THEN
      RAISE EXCEPTION 'That room belongs to another college';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ============================================================
-- 4. Subjects fill the section by themselves
--    A new section gets one row per subject of its program and year
--    level. A subject added later reaches the draft sections that
--    already exist. The Secretary then only picks professor, room, time.
-- ============================================================
-- Runs once per new section: subjects first, then the students waiting for a seat
-- (placement is defined in section 5), so the section is complete before anyone lands in it.
CREATE OR REPLACE FUNCTION after_section_created() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO section_subjects (section_id, subject_id)
  SELECT NEW.id, sub.id
    FROM subjects sub
   WHERE sub.program_id = NEW.program_id AND sub.year_level = NEW.year_level
   ON CONFLICT (section_id, subject_id) DO NOTHING;
  PERFORM place_waiting_students(NEW.program_id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION add_subject_to_draft_sections() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.year_level IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO section_subjects (section_id, subject_id)
  SELECT sec.id, NEW.id
    FROM sections sec
   WHERE sec.program_id = NEW.program_id AND sec.year_level = NEW.year_level AND sec.schedule_status = 'draft'
   ON CONFLICT (section_id, subject_id) DO NOTHING;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_subjects_add_to_sections AFTER INSERT ON subjects
    FOR EACH ROW EXECUTE FUNCTION add_subject_to_draft_sections();

-- ============================================================
-- 5. Automatic placement (decision-log.md #19)
--    place_student_in_section: first section of the student's program,
--    year level 1, with a free seat (by section name). Returns the
--    section, or null when there is none or the student is already
--    placed. Not callable by anyone: only the triggers below use it.
--    Year level 1 because the plan covers newly admitted students; the
--    Secretary or Dean moves a transferee who belongs higher up.
-- ============================================================
CREATE OR REPLACE FUNCTION place_student_in_section(p_student uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program uuid;
  v_user    uuid;
  v_sec     record;
BEGIN
  IF EXISTS (SELECT 1 FROM student_sections WHERE student_id = p_student) THEN
    RETURN NULL;
  END IF;

  SELECT a.program_id, a.user_id INTO v_program, v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;
  IF v_program IS NULL THEN
    RETURN NULL;
  END IF;

  -- Lock candidate sections in a fixed order so two placements cannot deadlock
  -- or both take the last seat.
  FOR v_sec IN
    SELECT sec.id, sec.name, sec.year_level, sec.capacity, p.code
      FROM sections sec JOIN programs p ON p.id = sec.program_id
     WHERE sec.program_id = v_program AND sec.year_level = 1
     ORDER BY sec.name, sec.id
       FOR UPDATE OF sec
  LOOP
    IF (SELECT count(*) FROM student_sections WHERE section_id = v_sec.id) < v_sec.capacity THEN
      INSERT INTO student_sections (student_id, section_id) VALUES (p_student, v_sec.id);
      INSERT INTO notifications (user_id, kind, title, message)
      VALUES (v_user, 'section_placed', 'Your section',
              'You are placed in ' || v_sec.code || ' Year ' || v_sec.year_level || ' - ' || v_sec.name
              || '. Your college is preparing your schedule.');
      RETURN v_sec.id;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

-- Everyone of one program still without a section, oldest promotion first,
-- until the seats run out. Returns how many were placed.
CREATE OR REPLACE FUNCTION place_waiting_students(p_program uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r      record;
  v_done integer := 0;
BEGIN
  FOR r IN
    SELECT st.id
      FROM students st JOIN applicants a ON a.id = st.applicant_id
     WHERE a.program_id = p_program
       AND NOT EXISTS (SELECT 1 FROM student_sections ss WHERE ss.student_id = st.id)
     ORDER BY st.documents_received_at, st.id
  LOOP
    EXIT WHEN place_student_in_section(r.id) IS NULL;
    v_done := v_done + 1;
  END LOOP;
  RETURN v_done;
END;
$$;

CREATE OR REPLACE FUNCTION trg_place_new_student() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM place_student_in_section(NEW.id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION trg_place_for_section() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM place_waiting_students(NEW.program_id);
  RETURN NULL;
END;
$$;

-- A placement never makes the promotion fail: with no section or no seat it
-- does nothing. The student then waits and is placed when seats appear.
CREATE TRIGGER trg_students_place AFTER INSERT ON students
    FOR EACH ROW EXECUTE FUNCTION trg_place_new_student();

CREATE TRIGGER trg_sections_created AFTER INSERT ON sections
    FOR EACH ROW EXECUTE FUNCTION after_section_created();
CREATE TRIGGER trg_sections_place_capacity AFTER UPDATE OF capacity ON sections
    FOR EACH ROW WHEN (NEW.capacity > OLD.capacity) EXECUTE FUNCTION trg_place_for_section();

-- ============================================================
-- 6. Move one student (decision-log.md #19)
--    Secretary or Dean of the student's college, or Admin. Any time
--    until the assessment slip is issued; after that the slip and the
--    section would disagree. May go over capacity. Also used to place
--    a student the automatic placement could not seat.
-- ============================================================
CREATE OR REPLACE FUNCTION move_student_section(p_student uuid, p_section uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role     text := app_role();
  v_program  uuid;
  v_user     uuid;
  v_sec      record;
  v_old      uuid;
  v_reason   text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary, the Dean or Admin can place students in sections';
  END IF;

  SELECT a.program_id, a.user_id INTO v_program, v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;

  SELECT sec.id, sec.name, sec.year_level, sec.program_id, p.code INTO v_sec
    FROM sections sec JOIN programs p ON p.id = sec.program_id
   WHERE sec.id = p_section;
  IF v_sec.id IS NULL THEN
    RAISE EXCEPTION 'Section not found';
  END IF;
  IF v_sec.program_id <> v_program THEN
    RAISE EXCEPTION 'A student can only be placed in a section of their own program';
  END IF;
  IF v_role <> 'admin' AND NOT program_in_my_college(v_program) THEN
    RAISE EXCEPTION 'This student belongs to another college';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips WHERE student_id = p_student) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the section can no longer be changed';
  END IF;

  SELECT section_id INTO v_old FROM student_sections WHERE student_id = p_student FOR UPDATE;
  IF v_old = p_section THEN
    RAISE EXCEPTION 'The student is already in this section';
  END IF;

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', v_reason, true);
  END IF;

  IF v_old IS NULL THEN
    INSERT INTO student_sections (student_id, section_id) VALUES (p_student, p_section);
  ELSE
    UPDATE student_sections SET section_id = p_section WHERE student_id = p_student;
  END IF;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user,
          CASE WHEN v_old IS NULL THEN 'section_placed' ELSE 'section_moved' END,
          CASE WHEN v_old IS NULL THEN 'Your section' ELSE 'Your section has changed' END,
          'You are placed in ' || v_sec.code || ' Year ' || v_sec.year_level || ' - ' || v_sec.name
          || '. Your college is preparing your schedule.');

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;
  RETURN p_section;
END;
$$;

-- ============================================================
-- 7. Reject a schedule (decision-log.md #18)
--    The reason must be in the same transaction as the status change,
--    so this is a function. The gate trigger decides who may reject
--    from which status and stores the reason.
-- ============================================================
CREATE OR REPLACE FUNCTION reject_schedule(p_section uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role   text := app_role();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_status text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','registrar','admin') THEN
    RAISE EXCEPTION 'Only the Dean or the Registrar can reject a schedule';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A reason is required to reject a schedule';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  SELECT schedule_status INTO v_status FROM sections WHERE id = p_section;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Section not found';
  END IF;
  IF v_status NOT IN ('pending_dean','dean_signed') THEN
    RAISE EXCEPTION 'Only a schedule waiting for the Dean or for the Registrar can be rejected';
  END IF;

  PERFORM set_config('app.audit_reason', v_reason, true);
  UPDATE sections SET schedule_status = 'draft' WHERE id = p_section;
  PERFORM set_config('app.audit_reason', '', true);
END;
$$;

-- ============================================================
-- 8. Tell the students when their schedule is approved
-- ============================================================
CREATE OR REPLACE FUNCTION notify_schedule_approved() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_code text;
BEGIN
  SELECT code INTO v_code FROM programs WHERE id = NEW.program_id;
  INSERT INTO notifications (user_id, kind, title, message)
  SELECT a.user_id, 'schedule_approved', 'Your schedule is approved',
         'The schedule for ' || v_code || ' Year ' || NEW.year_level || ' - ' || NEW.name
         || ' is approved. Your next step is the assessment slip from the Registrar.'
    FROM student_sections ss
    JOIN students st ON st.id = ss.student_id
    JOIN applicants a ON a.id = st.applicant_id
   WHERE ss.section_id = NEW.id;
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_sections_approved_notify AFTER UPDATE OF schedule_status ON sections
    FOR EACH ROW WHEN (NEW.schedule_status = 'approved' AND OLD.schedule_status IS DISTINCT FROM 'approved')
    EXECUTE FUNCTION notify_schedule_approved();

-- ============================================================
-- 9. The Registrar approves loading, so the Registrar reads the
--    Professors named in it (names only, no other role's rows).
-- ============================================================
CREATE POLICY users_registrar_professors ON users FOR SELECT TO authenticated
    USING (app_role() = 'registrar' AND role = 'professor');

-- ============================================================
-- 10. Who may call them. The functions also check the role themselves.
--     The placement and trigger functions are internal: nobody calls them.
-- ============================================================
REVOKE EXECUTE ON FUNCTION move_student_section(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION reject_schedule(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION place_student_in_section(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION place_waiting_students(uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION move_student_section(uuid, uuid, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION reject_schedule(uuid, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION place_student_in_section(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION place_waiting_students(uuid) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION place_student_in_section(uuid) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION place_waiting_students(uuid) FROM authenticated;
  END IF;
END $$;
