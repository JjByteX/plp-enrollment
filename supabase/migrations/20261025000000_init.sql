-- ============================================================
-- supabase/migrations/20261025000000_init.sql
-- PLP Enrollment: initial schema
--
-- Encodes the decisions in docs/enrollment-plan.md: RBAC roles enforced
-- by row level security, the Applicant -> Student promotion, automatic
-- one-time student numbering, the Secretary prepares / Dean signs off /
-- Registrar approves schedule chain, the per-course payment toggle, the
-- two reschedule paths, and an audit log.
--
-- This is a SEPARATE database from PLP Admissions. The only link between
-- the two systems is admissions_intake_log, which records what the
-- inbound webhook received.
--
-- Nothing here has been applied to any database yet, so this file is
-- still edited in place. Once it is merged to main, never edit it again:
-- add a new migration (forward-only).
--
-- How the database knows who is acting (used by RLS, the gates and the
-- audit log): current_actor_id() reads the signed-in Supabase user
-- (auth.uid()) and falls back to the setting app.actor_id, which server
-- code sets per transaction with: SELECT set_config('app.actor_id', '<users.id>', true);
-- Optional reason for the audit log: set_config('app.audit_reason', '<why>', true).
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "citext" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "extensions";

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 1. Colleges, users and roles (RBAC: enrollment-plan.md Access section)
-- ============================================================
CREATE TABLE colleges (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        varchar(150) NOT NULL,
    code        varchar(20) NOT NULL UNIQUE
);

CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id         uuid NOT NULL UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
    full_name       varchar(150) NOT NULL,
    email           citext NOT NULL UNIQUE,
    role            text NOT NULL
                    CHECK (role IN ('applicant','student','registrar','finance','dean','college_secretary','professor','admin')),
    college_id      uuid NULL REFERENCES colleges (id), -- Dean and College Secretary only
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_college_required CHECK (role NOT IN ('dean','college_secretary') OR college_id IS NOT NULL)
);
CREATE INDEX idx_users_role ON users (role);
CREATE INDEX idx_users_college ON users (college_id);
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON COLUMN users.role IS 'admin has every permission of every other role per enrollment-plan.md Decided section';
COMMENT ON COLUMN users.college_id IS 'Deans and College Secretaries are limited to one college (enrollment-plan.md Access table)';

-- Who is acting. SECURITY DEFINER so RLS on users does not block the lookup.
CREATE OR REPLACE FUNCTION current_actor_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    (SELECT u.id FROM users u WHERE u.auth_id = auth.uid() AND u.is_active),
    nullif(current_setting('app.actor_id', true), '')::uuid
  )
$$;

CREATE OR REPLACE FUNCTION app_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.role FROM users u WHERE u.id = current_actor_id() AND u.is_active
$$;

CREATE OR REPLACE FUNCTION app_college_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.college_id FROM users u WHERE u.id = current_actor_id() AND u.is_active
$$;

-- ============================================================
-- 2. Programs. Must mirror Admissions' 13 program codes exactly,
--    including BSENT (enrollment-plan.md, Connection section).
--    The codes are not seeded here: see open-questions.md.
-- ============================================================
CREATE TABLE programs (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        varchar(20) NOT NULL UNIQUE, -- must match Admissions' program codes
    name        varchar(150) NOT NULL,
    college_id  uuid NOT NULL REFERENCES colleges (id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_programs_updated_at BEFORE UPDATE ON programs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- The payment toggle lives in its own table so row level security can hide
-- it from Students, Applicants, Secretaries and Professors.
CREATE TABLE program_payment_settings (
    program_id        uuid PRIMARY KEY REFERENCES programs (id) ON DELETE CASCADE,
    payment_required  boolean NOT NULL DEFAULT false,
    updated_by        uuid NULL REFERENCES users (id),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE program_payment_settings IS 'Per-course payment toggle. Admin and Finance can change it; Registrar and Dean can see it but not change it. Every change is audit-logged.';

CREATE OR REPLACE FUNCTION create_program_payment_setting() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO program_payment_settings (program_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_programs_payment_setting AFTER INSERT ON programs
    FOR EACH ROW EXECUTE FUNCTION create_program_payment_setting();

CREATE OR REPLACE FUNCTION stamp_payment_setting() RETURNS trigger AS $$
BEGIN
  NEW.updated_by = current_actor_id();
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_payment_setting_stamp BEFORE UPDATE ON program_payment_settings
    FOR EACH ROW EXECUTE FUNCTION stamp_payment_setting();

-- ============================================================
-- 3. Admissions intake: the inbound webhook log
--    See enrollment-plan.md: Connection to PLP Admissions.
--    NOTE: as of 2026-10-24 the Admissions codebase does not yet send
--    this payload (see open-questions.md and decision-log.md #6).
-- ============================================================
CREATE TABLE admissions_intake_log (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_ref           varchar(40) NOT NULL, -- e.g. ADM-2026-000042, never changes, catches duplicates
    full_name               varchar(150) NOT NULL,
    email                   citext NOT NULL,
    program_code            varchar(20) NOT NULL,
    admission_date          date NOT NULL,
    admission_type          text NOT NULL CHECK (admission_type IN ('new','transferee')),
    source_name             varchar(60) NOT NULL DEFAULT 'PLP Admissions',
    received_at             timestamptz NOT NULL DEFAULT now(),
    status                  text NOT NULL CHECK (status IN ('accepted','rejected')),
    rejection_reason        text NULL, -- e.g. unrecognized program code
    raw_payload             jsonb NOT NULL,
    resulting_applicant_id  uuid NULL -- FK added below, once applicants exists
);
CREATE INDEX idx_intake_ref ON admissions_intake_log (applicant_ref);
CREATE INDEX idx_intake_status ON admissions_intake_log (status);
COMMENT ON TABLE admissions_intake_log IS 'Every request received from Admissions, successful or failed, with who sent it and when. Admin can view all of these, resend a failed one, and toggle the connection on/off.';

CREATE TABLE admissions_connection_settings (
    id          boolean PRIMARY KEY DEFAULT true CHECK (id), -- singleton row
    is_enabled  boolean NOT NULL DEFAULT true,
    updated_by  uuid NULL REFERENCES users (id),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO admissions_connection_settings (id, is_enabled) VALUES (true, true);

-- ============================================================
-- 4. Applicants and Students
--    An Applicant becomes a Student exactly when the Registrar marks
--    documents received: that inserts the students row, which gets its
--    number automatically and flips the user's role.
-- ============================================================
CREATE TABLE applicants (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL UNIQUE REFERENCES users (id),
    applicant_ref   varchar(40) NOT NULL UNIQUE, -- from Admissions
    program_id      uuid NOT NULL REFERENCES programs (id),
    admission_date  date NOT NULL,
    admission_type  text NOT NULL CHECK (admission_type IN ('new','transferee')),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_applicants_program ON applicants (program_id);
CREATE TRIGGER trg_applicants_updated_at BEFORE UPDATE ON applicants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE admissions_intake_log
    ADD CONSTRAINT fk_intake_applicant FOREIGN KEY (resulting_applicant_id) REFERENCES applicants (id);

-- One number per student, never reused, never edited. A sequence never
-- hands out the same value twice.
CREATE SEQUENCE student_number_seq START 1;

-- The student number format is NOT decided yet (open-questions.md).
-- This is the one place to change it. Today: 8 digit zero padded sequence.
CREATE OR REPLACE FUNCTION generate_student_number() RETURNS varchar
LANGUAGE sql VOLATILE AS $$
  SELECT to_char(nextval('student_number_seq'), 'FM00000000')::varchar
$$;

CREATE TABLE students (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id            uuid NOT NULL UNIQUE REFERENCES applicants (id),
    student_number          varchar(20) NOT NULL UNIQUE, -- set by trg_students_promote, never typed
    documents_received_at   timestamptz NOT NULL DEFAULT now(),
    documents_received_by   uuid NOT NULL REFERENCES users (id),
    created_at              timestamptz NOT NULL DEFAULT now()
);

-- Promotion: only Registrar/Admin, nobody types the number, and the
-- applicant's account becomes a student account in the same transaction.
CREATE OR REPLACE FUNCTION promote_applicant_to_student() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can mark documents received';
  END IF;
  NEW.student_number := generate_student_number();
  NEW.documents_received_at := now();
  NEW.documents_received_by := current_actor_id();
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_students_promote BEFORE INSERT ON students
    FOR EACH ROW EXECUTE FUNCTION promote_applicant_to_student();

CREATE OR REPLACE FUNCTION flip_user_to_student() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE users SET role = 'student'
  WHERE id = (SELECT a.user_id FROM applicants a WHERE a.id = NEW.applicant_id);
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_students_flip_role AFTER INSERT ON students
    FOR EACH ROW EXECUTE FUNCTION flip_user_to_student();

CREATE OR REPLACE FUNCTION prevent_student_number_edit() RETURNS trigger AS $$
BEGIN
  IF NEW.student_number IS DISTINCT FROM OLD.student_number THEN
    RAISE EXCEPTION 'student_number cannot be changed once assigned';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_students_no_number_edit BEFORE UPDATE ON students
    FOR EACH ROW EXECUTE FUNCTION prevent_student_number_edit();

-- Uploaded originals (birth certificate, report card, IDs). Registrar and
-- Admin only. Files live in Supabase Storage, this row points at them.
CREATE TABLE documents (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id  uuid NOT NULL REFERENCES applicants (id),
    doc_type      text NOT NULL CHECK (doc_type IN ('birth_certificate','report_card','id','other')),
    storage_path  text NOT NULL,
    uploaded_by   uuid NOT NULL REFERENCES users (id),
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_documents_applicant ON documents (applicant_id);

-- ============================================================
-- 5. Visit scheduling (decided model: date + time window + per-program
--    capacity; "next available" = earliest slot of the same program with
--    open capacity). Staff create slots and assign applicants; nobody
--    picks their own slot.
-- ============================================================
CREATE TABLE visit_slots (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id   uuid NOT NULL REFERENCES programs (id),
    slot_date    date NOT NULL,
    start_time   time NOT NULL,
    end_time     time NOT NULL,
    capacity     integer NOT NULL CHECK (capacity > 0),
    office_name  varchar(100) NOT NULL, -- shown on the "Your next step" card
    status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','cancelled')),
    created_by   uuid NULL REFERENCES users (id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT visit_slots_time_order CHECK (end_time > start_time),
    CONSTRAINT visit_slots_unique UNIQUE (program_id, slot_date, start_time, office_name)
);
CREATE INDEX idx_visit_slots_lookup ON visit_slots (program_id, slot_date, start_time) WHERE status = 'open';
CREATE TRIGGER trg_visit_slots_updated_at BEFORE UPDATE ON visit_slots
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE visit_bookings (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slot_id       uuid NOT NULL REFERENCES visit_slots (id),
    applicant_id  uuid NOT NULL UNIQUE REFERENCES applicants (id), -- one visit per applicant; a reschedule changes slot_id
    status        text NOT NULL DEFAULT 'booked' CHECK (status IN ('booked','attended','no_show')),
    assigned_by   uuid NULL REFERENCES users (id), -- null = assigned by the system
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_visit_bookings_slot ON visit_bookings (slot_id);
CREATE TRIGGER trg_visit_bookings_updated_at BEFORE UPDATE ON visit_bookings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Capacity and program match, race safe (locks the slot row).
CREATE OR REPLACE FUNCTION enforce_booking_capacity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slot visit_slots%ROWTYPE;
  v_program uuid;
  v_taken integer;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.slot_id = OLD.slot_id THEN
    RETURN NEW; -- status change only
  END IF;
  SELECT * INTO v_slot FROM visit_slots WHERE id = NEW.slot_id FOR UPDATE;
  IF v_slot.status <> 'open' THEN
    RAISE EXCEPTION 'This visit slot is not open';
  END IF;
  SELECT program_id INTO v_program FROM applicants WHERE id = NEW.applicant_id;
  IF v_program IS DISTINCT FROM v_slot.program_id THEN
    RAISE EXCEPTION 'Visit slot is for a different program';
  END IF;
  SELECT count(*) INTO v_taken FROM visit_bookings
    WHERE slot_id = NEW.slot_id AND id <> NEW.id;
  IF v_taken >= v_slot.capacity THEN
    RAISE EXCEPTION 'This visit slot is full';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_visit_bookings_capacity BEFORE INSERT OR UPDATE OF slot_id ON visit_bookings
    FOR EACH ROW EXECUTE FUNCTION enforce_booking_capacity();

-- ============================================================
-- 6. Subjects, rooms, sections and the schedule approval chain
--    Secretary prepares -> Dean signs off professor loading ->
--    Registrar approves. The three gates cannot be skipped or reordered.
-- ============================================================
CREATE TABLE subjects (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id  uuid NOT NULL REFERENCES programs (id),
    code        varchar(30) NOT NULL,
    title       varchar(200) NOT NULL,
    units       numeric(3,1) NOT NULL CHECK (units >= 0),
    year_level  smallint NULL,
    UNIQUE (program_id, code)
);

CREATE TABLE rooms (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        varchar(80) NOT NULL UNIQUE,
    capacity    integer NULL CHECK (capacity > 0),
    college_id  uuid NULL REFERENCES colleges (id)
);

CREATE TABLE sections (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id       uuid NOT NULL REFERENCES programs (id),
    name             varchar(50) NOT NULL,
    year_level       smallint NOT NULL,
    schedule_status  text NOT NULL DEFAULT 'draft'
                     CHECK (schedule_status IN ('draft','pending_dean','dean_signed','approved')),
    prepared_by      uuid NULL REFERENCES users (id),
    dean_signed_by   uuid NULL REFERENCES users (id),
    dean_signed_at   timestamptz NULL,
    approved_by      uuid NULL REFERENCES users (id),
    approved_at      timestamptz NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (program_id, year_level, name)
);
CREATE TRIGGER trg_sections_updated_at BEFORE UPDATE ON sections
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION enforce_section_gates() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_college uuid;
BEGIN
  IF NEW.schedule_status = OLD.schedule_status THEN
    -- the sign-off columns are only ever set by a status change
    NEW.prepared_by := OLD.prepared_by;
    NEW.dean_signed_by := OLD.dean_signed_by;
    NEW.dean_signed_at := OLD.dean_signed_at;
    NEW.approved_by := OLD.approved_by;
    NEW.approved_at := OLD.approved_at;
    IF v_role = 'registrar' AND (NEW.program_id, NEW.name, NEW.year_level)
       IS DISTINCT FROM (OLD.program_id, OLD.name, OLD.year_level) THEN
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
    NEW.prepared_by := v_actor;
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
  ELSE
    RAISE EXCEPTION 'Invalid schedule status change: % to %', OLD.schedule_status, NEW.schedule_status;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_sections_gates BEFORE UPDATE ON sections
    FOR EACH ROW EXECUTE FUNCTION enforce_section_gates();

-- One row per subject taught in a section: professor, room and time.
CREATE TABLE section_subjects (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id    uuid NOT NULL REFERENCES sections (id) ON DELETE CASCADE,
    subject_id    uuid NOT NULL REFERENCES subjects (id),
    professor_id  uuid NULL REFERENCES users (id),
    room_id       uuid NULL REFERENCES rooms (id),
    day_of_week   smallint NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time    time NULL,
    end_time      time NULL,
    slot_range    int4range GENERATED ALWAYS AS (
                    int4range((extract(epoch FROM start_time) / 60)::int, (extract(epoch FROM end_time) / 60)::int)
                  ) STORED,
    UNIQUE (section_id, subject_id),
    CONSTRAINT section_subjects_time_pair CHECK (
        (start_time IS NULL AND end_time IS NULL AND day_of_week IS NULL)
        OR (start_time IS NOT NULL AND end_time IS NOT NULL AND day_of_week IS NOT NULL AND end_time > start_time)
    ),
    -- No room or professor can be in two places at the same time.
    CONSTRAINT section_subjects_no_room_clash EXCLUDE USING gist
        (room_id WITH =, day_of_week WITH =, slot_range WITH &&)
        WHERE (room_id IS NOT NULL AND day_of_week IS NOT NULL),
    CONSTRAINT section_subjects_no_professor_clash EXCLUDE USING gist
        (professor_id WITH =, day_of_week WITH =, slot_range WITH &&)
        WHERE (professor_id IS NOT NULL AND day_of_week IS NOT NULL)
);
CREATE INDEX idx_section_subjects_professor ON section_subjects (professor_id);

-- Professor loading can only change while the section is still a draft,
-- and only users with the Professor role can be assigned.
CREATE OR REPLACE FUNCTION enforce_section_subject_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_section uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.section_id ELSE NEW.section_id END;
  v_status text;
BEGIN
  SELECT schedule_status INTO v_status FROM sections WHERE id = v_section;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'The schedule is already submitted; professor loading is locked';
  END IF;
  IF TG_OP <> 'DELETE' AND NEW.professor_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.professor_id AND role = 'professor' AND is_active) THEN
    RAISE EXCEPTION 'Assigned user is not an active Professor';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
CREATE TRIGGER trg_section_subjects_rules BEFORE INSERT OR UPDATE OR DELETE ON section_subjects
    FOR EACH ROW EXECUTE FUNCTION enforce_section_subject_rules();

-- Which section a student belongs to (Secretary / Dean place them).
CREATE TABLE student_sections (
    student_id  uuid PRIMARY KEY REFERENCES students (id),
    section_id  uuid NOT NULL REFERENCES sections (id),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_student_sections_section ON student_sections (section_id);

-- ============================================================
-- 7. Assessment slip -> payment (only if required) -> COR
-- ============================================================
CREATE TABLE assessment_slips (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        uuid NOT NULL UNIQUE REFERENCES students (id),
    payment_required  boolean NOT NULL, -- snapshot of the program toggle at issue time
    issued_by         uuid NOT NULL REFERENCES users (id),
    issued_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payments (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL UNIQUE REFERENCES students (id),
    amount_due    numeric(12,2) NULL CHECK (amount_due >= 0), -- Finance enters it
    amount_paid   numeric(12,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    receipt_no    varchar(60) NULL,
    status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','cleared')),
    recorded_by   uuid NULL REFERENCES users (id),
    cleared_at    timestamptz NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payments_cleared_complete CHECK (
        status = 'pending'
        OR (amount_due IS NOT NULL AND amount_paid >= amount_due AND recorded_by IS NOT NULL AND cleared_at IS NOT NULL)
    )
);
CREATE TRIGGER trg_payments_updated_at BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE cors (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL UNIQUE REFERENCES students (id),
    issued_by   uuid NOT NULL REFERENCES users (id),
    issued_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE cors IS 'A row here means the student is enrolled. COR layout/fields are an open question (open-questions.md).';

-- Slip: Registrar/Admin only, and only after the student's schedule is approved.
CREATE OR REPLACE FUNCTION enforce_slip_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_status text;
  v_program uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue an assessment slip';
  END IF;
  SELECT s.schedule_status INTO v_status
    FROM student_sections ss JOIN sections s ON s.id = ss.section_id
    WHERE ss.student_id = NEW.student_id;
  IF v_status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'The student''s schedule must be approved before the assessment slip';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = NEW.student_id;
  NEW.payment_required := coalesce(
    (SELECT payment_required FROM program_payment_settings WHERE program_id = v_program), false);
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_slips_gate BEFORE INSERT ON assessment_slips
    FOR EACH ROW EXECUTE FUNCTION enforce_slip_gate();

-- When payment is required, the slip opens a pending payment for Finance.
CREATE OR REPLACE FUNCTION open_payment_after_slip() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.payment_required THEN
    INSERT INTO payments (student_id) VALUES (NEW.student_id);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_slips_open_payment AFTER INSERT ON assessment_slips
    FOR EACH ROW EXECUTE FUNCTION open_payment_after_slip();

-- Payment: only Finance/Admin clear it.
CREATE OR REPLACE FUNCTION enforce_payment_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance can record payment';
  END IF;
  IF NEW.status = 'cleared' AND OLD.status = 'pending' THEN
    NEW.recorded_by := current_actor_id();
    NEW.cleared_at := now();
  ELSIF OLD.status = 'cleared' THEN
    RAISE EXCEPTION 'A cleared payment cannot be changed';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payments_gate BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION enforce_payment_gate();

-- COR: Registrar/Admin only, after the slip, and after payment when required.
CREATE OR REPLACE FUNCTION enforce_cor_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slip assessment_slips%ROWTYPE;
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
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_cors_gate BEFORE INSERT ON cors
    FOR EACH ROW EXECUTE FUNCTION enforce_cor_gate();

-- ============================================================
-- 8. Reschedules: two separate paths (decision-log.md #5).
--    These tables record the request/event. Moving bookings is done by
--    server code, never by the student.
-- ============================================================
CREATE TABLE mass_reschedules (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    affected_date   date NOT NULL,
    program_id      uuid NULL REFERENCES programs (id), -- optional filter
    office_name     varchar(100) NULL,                  -- optional filter
    reason          text NOT NULL,
    target_slot_id  uuid NULL REFERENCES visit_slots (id), -- NULL = move to next available slot
    triggered_by    uuid NOT NULL REFERENCES users (id),
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION enforce_mass_reschedule_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can set a mass reschedule';
  END IF;
  NEW.triggered_by := current_actor_id();
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_mass_reschedules_gate BEFORE INSERT ON mass_reschedules
    FOR EACH ROW EXECUTE FUNCTION enforce_mass_reschedule_gate();

CREATE TABLE reschedule_requests (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id     uuid NOT NULL REFERENCES visit_bookings (id),
    requested_by   uuid NOT NULL REFERENCES users (id),
    reason         text NOT NULL,
    status         text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','declined')),
    new_slot_id    uuid NULL REFERENCES visit_slots (id), -- slot given on approval, or offered on decline
    decision_note  text NULL,
    decided_by     uuid NULL REFERENCES users (id),
    decided_at     timestamptz NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT reschedule_requests_decided CHECK (
        status = 'pending' OR (decided_by IS NOT NULL AND decided_at IS NOT NULL)
    )
);
CREATE UNIQUE INDEX uq_reschedule_one_pending ON reschedule_requests (booking_id) WHERE status = 'pending';

CREATE OR REPLACE FUNCTION enforce_reschedule_request_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.decided_by := NULL;
    NEW.decided_at := NULL;
    NEW.new_slot_id := NULL;
    NEW.decision_note := NULL;
    RETURN NEW;
  END IF;
  IF OLD.status <> 'pending' THEN
    RAISE EXCEPTION 'This request has already been decided';
  END IF;
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can approve or decline a reschedule request';
  END IF;
  IF NEW.status <> 'pending' THEN
    NEW.decided_by := current_actor_id();
    NEW.decided_at := now();
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_reschedule_requests_gate BEFORE INSERT OR UPDATE ON reschedule_requests
    FOR EACH ROW EXECUTE FUNCTION enforce_reschedule_request_gate();

-- ============================================================
-- 9. Notifications: the "Your next step" message and the email behind it.
-- ============================================================
CREATE TABLE notifications (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES users (id),
    kind            text NOT NULL, -- e.g. visit_assigned, mass_rescheduled, request_approved
    title           varchar(200) NOT NULL,
    message         text NOT NULL,
    office_name     varchar(100) NULL,
    window_label    varchar(100) NULL,
    scheduled_for   timestamptz NULL,
    what_to_bring   text NULL,
    email_status    text NOT NULL DEFAULT 'pending' CHECK (email_status IN ('pending','sent','failed','not_needed')),
    email_sent_at   timestamptz NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications (user_id, created_at DESC);

-- ============================================================
-- 10. Audit log: append only. Who, what, when (and why when given).
-- ============================================================
CREATE TABLE audit_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id    uuid NULL,   -- null = server/system action
    actor_role  text NULL,
    action      text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    table_name  text NOT NULL,
    record_id   text NULL,
    old_data    jsonb NULL,
    new_data    jsonb NULL,
    reason      text NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_table ON audit_log (table_name, created_at DESC);
CREATE INDEX idx_audit_actor ON audit_log (actor_id, created_at DESC);

CREATE OR REPLACE FUNCTION audit_log_append_only() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append only';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_no_change BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_append_only();
CREATE TRIGGER trg_audit_no_truncate BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_append_only();
REVOKE UPDATE, DELETE, TRUNCATE ON audit_log FROM PUBLIC;

CREATE OR REPLACE FUNCTION log_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_old jsonb := CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END;
  v_new jsonb := CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END;
BEGIN
  IF TG_OP = 'UPDATE' AND v_old = v_new THEN
    RETURN NULL;
  END IF;
  INSERT INTO audit_log (actor_id, actor_role, action, table_name, record_id, old_data, new_data, reason)
  VALUES (
    current_actor_id(), app_role(), TG_OP, TG_TABLE_NAME,
    coalesce(v_new, v_old)->>'id',
    v_old, v_new,
    nullif(current_setting('app.audit_reason', true), '')
  );
  RETURN NULL;
END;
$$;

-- Every table staff or Admin can write, so every Admin action is logged
-- like everyone else's. audit_log itself and the intake log are not
-- audited (the intake log is its own record).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'colleges','users','programs','program_payment_settings','admissions_connection_settings',
    'applicants','students','documents','visit_slots','visit_bookings','subjects','rooms',
    'sections','section_subjects','student_sections','assessment_slips','payments','cors',
    'mass_reschedules','reschedule_requests'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION log_audit()', t);
  END LOOP;
END $$;

-- ============================================================
-- 11. Row level security. Deny by default: a table with RLS on and no
--     matching policy returns nothing. Policies follow the Access table
--     in enrollment-plan.md. Server code that connects as a superuser
--     (lib/db.ts) bypasses RLS: see open-questions.md.
-- ============================================================
CREATE OR REPLACE FUNCTION my_applicant_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.id FROM applicants a WHERE a.user_id = current_actor_id()
$$;

CREATE OR REPLACE FUNCTION my_student_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id FROM students s JOIN applicants a ON a.id = s.applicant_id WHERE a.user_id = current_actor_id()
$$;

-- Is this program in the college of the signed-in Dean / Secretary?
CREATE OR REPLACE FUNCTION program_in_my_college(p_program uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM programs p WHERE p.id = p_program AND p.college_id = app_college_id())
$$;

CREATE OR REPLACE FUNCTION user_in_my_college(p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM applicants a JOIN programs p ON p.id = a.program_id
    WHERE a.user_id = p_user AND p.college_id = app_college_id())
$$;

CREATE OR REPLACE FUNCTION applicant_in_my_college(p_applicant uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM applicants a JOIN programs p ON p.id = a.program_id
    WHERE a.id = p_applicant AND p.college_id = app_college_id())
$$;

CREATE OR REPLACE FUNCTION student_in_my_college(p_student uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM students s JOIN applicants a ON a.id = s.applicant_id
    JOIN programs p ON p.id = a.program_id
    WHERE s.id = p_student AND p.college_id = app_college_id())
$$;

CREATE OR REPLACE FUNCTION section_in_my_college(p_section uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM sections s JOIN programs p ON p.id = s.program_id
    WHERE s.id = p_section AND p.college_id = app_college_id())
$$;

CREATE OR REPLACE FUNCTION professor_teaches_section(p_section uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM section_subjects ss WHERE ss.section_id = p_section AND ss.professor_id = current_actor_id())
$$;

CREATE OR REPLACE FUNCTION my_section_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT ss.section_id FROM student_sections ss WHERE ss.student_id = my_student_id()
$$;

CREATE OR REPLACE FUNCTION my_visit_slot_ids() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT vb.slot_id FROM visit_bookings vb WHERE vb.applicant_id = my_applicant_id()
$$;

ALTER TABLE colleges                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                          ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_payment_settings       ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions_intake_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions_connection_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE applicants                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE students                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_slots                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_bookings                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                          ENABLE ROW LEVEL SECURITY;
ALTER TABLE sections                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE section_subjects               ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_sections               ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_slips               ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cors                           ENABLE ROW LEVEL SECURITY;
ALTER TABLE mass_reschedules               ENABLE ROW LEVEL SECURITY;
ALTER TABLE reschedule_requests            ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log                      ENABLE ROW LEVEL SECURITY;

-- Admin does everything on every table (enrollment-plan.md Decided).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'colleges','users','programs','program_payment_settings','admissions_intake_log',
    'admissions_connection_settings','applicants','students','documents','visit_slots',
    'visit_bookings','subjects','rooms','sections','section_subjects','student_sections',
    'assessment_slips','payments','cors','mass_reschedules','reschedule_requests','notifications'
  ] LOOP
    EXECUTE format(
      'CREATE POLICY admin_all ON %I FOR ALL TO authenticated USING (app_role() = ''admin'') WITH CHECK (app_role() = ''admin'')', t);
  END LOOP;
END $$;
CREATE POLICY admin_read ON audit_log FOR SELECT TO authenticated USING (app_role() = 'admin');

-- Reference data everyone signed in may read.
CREATE POLICY read_all ON colleges FOR SELECT TO authenticated USING (true);
CREATE POLICY read_all ON programs FOR SELECT TO authenticated USING (true);

-- users
CREATE POLICY users_self ON users FOR SELECT TO authenticated USING (id = current_actor_id());
CREATE POLICY users_registrar ON users FOR SELECT TO authenticated
    USING (app_role() = 'registrar' AND role IN ('applicant','student'));
CREATE POLICY users_finance ON users FOR SELECT TO authenticated
    USING (app_role() = 'finance' AND role = 'student');
CREATE POLICY users_college_staff ON users FOR SELECT TO authenticated
    USING (app_role() IN ('dean','college_secretary')
           AND (role = 'professor' OR (role IN ('applicant','student') AND user_in_my_college(id))));

-- program_payment_settings: Finance changes it; Registrar and Dean only see it
CREATE POLICY pps_read ON program_payment_settings FOR SELECT TO authenticated
    USING (app_role() IN ('finance','registrar','dean'));
CREATE POLICY pps_finance_update ON program_payment_settings FOR UPDATE TO authenticated
    USING (app_role() = 'finance') WITH CHECK (app_role() = 'finance');

-- applicants
CREATE POLICY applicants_self ON applicants FOR SELECT TO authenticated USING (user_id = current_actor_id());
CREATE POLICY applicants_registrar ON applicants FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY applicants_college ON applicants FOR SELECT TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND program_in_my_college(program_id));

-- students
CREATE POLICY students_self ON students FOR SELECT TO authenticated USING (id = my_student_id());
CREATE POLICY students_registrar_finance ON students FOR SELECT TO authenticated
    USING (app_role() IN ('registrar','finance'));
CREATE POLICY students_college ON students FOR SELECT TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND student_in_my_college(id));
CREATE POLICY students_registrar_insert ON students FOR INSERT TO authenticated
    WITH CHECK (app_role() = 'registrar');

-- documents: Registrar and Admin only
CREATE POLICY documents_registrar ON documents FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');

-- visit slots and bookings
CREATE POLICY slots_registrar ON visit_slots FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY slots_mine ON visit_slots FOR SELECT TO authenticated USING (id IN (SELECT my_visit_slot_ids()));
CREATE POLICY bookings_registrar ON visit_bookings FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY bookings_self ON visit_bookings FOR SELECT TO authenticated USING (applicant_id = my_applicant_id());

-- subjects and rooms: staff read, Admin writes
CREATE POLICY subjects_read ON subjects FOR SELECT TO authenticated
    USING (app_role() IN ('registrar','dean','college_secretary','professor'));
CREATE POLICY rooms_read ON rooms FOR SELECT TO authenticated
    USING (app_role() IN ('registrar','dean','college_secretary'));

-- sections and their loading
CREATE POLICY sections_registrar ON sections FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY sections_registrar_approve ON sections FOR UPDATE TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY sections_college ON sections FOR ALL TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND program_in_my_college(program_id))
    WITH CHECK (app_role() IN ('dean','college_secretary') AND program_in_my_college(program_id));
CREATE POLICY sections_professor ON sections FOR SELECT TO authenticated
    USING (app_role() = 'professor' AND professor_teaches_section(id));
CREATE POLICY sections_student ON sections FOR SELECT TO authenticated USING (id = my_section_id());

CREATE POLICY section_subjects_registrar ON section_subjects FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY section_subjects_college ON section_subjects FOR ALL TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND section_in_my_college(section_id))
    WITH CHECK (app_role() IN ('dean','college_secretary') AND section_in_my_college(section_id));
CREATE POLICY section_subjects_professor ON section_subjects FOR SELECT TO authenticated
    USING (app_role() = 'professor' AND professor_id = current_actor_id());
CREATE POLICY section_subjects_student ON section_subjects FOR SELECT TO authenticated USING (section_id = my_section_id());

CREATE POLICY student_sections_self ON student_sections FOR SELECT TO authenticated USING (student_id = my_student_id());
CREATE POLICY student_sections_registrar ON student_sections FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY student_sections_college ON student_sections FOR ALL TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND student_in_my_college(student_id))
    WITH CHECK (app_role() IN ('dean','college_secretary') AND student_in_my_college(student_id));

-- slip, payment, COR
CREATE POLICY slips_self ON assessment_slips FOR SELECT TO authenticated USING (student_id = my_student_id());
CREATE POLICY slips_registrar ON assessment_slips FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY payments_finance ON payments FOR ALL TO authenticated
    USING (app_role() = 'finance') WITH CHECK (app_role() = 'finance');
CREATE POLICY payments_registrar_read ON payments FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY cors_self ON cors FOR SELECT TO authenticated USING (student_id = my_student_id());
CREATE POLICY cors_registrar ON cors FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');

-- reschedules
CREATE POLICY mass_reschedules_registrar ON mass_reschedules FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY requests_registrar ON reschedule_requests FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY requests_self_read ON reschedule_requests FOR SELECT TO authenticated USING (requested_by = current_actor_id());
-- Students (not Applicants) may file a request for their own booking, per the Access table.
-- Open question: Applicants visit before they become Students (open-questions.md).
CREATE POLICY requests_student_insert ON reschedule_requests FOR INSERT TO authenticated
    WITH CHECK (
      app_role() = 'student'
      AND requested_by = current_actor_id()
      AND booking_id IN (SELECT vb.id FROM visit_bookings vb WHERE vb.applicant_id = my_applicant_id())
    );

-- notifications: your own only
CREATE POLICY notifications_self ON notifications FOR SELECT TO authenticated USING (user_id = current_actor_id());

-- Professors see class lists (name and student number only), never the
-- students table. The view runs with its owner's rights and filters itself.
CREATE VIEW professor_class_lists AS
SELECT DISTINCT ss.section_id, sec.name AS section_name, sub.code AS subject_code, sub.title AS subject_title,
       st.student_number, u.full_name
FROM section_subjects ss
JOIN sections sec ON sec.id = ss.section_id
JOIN subjects sub ON sub.id = ss.subject_id
JOIN student_sections sts ON sts.section_id = ss.section_id
JOIN students st ON st.id = sts.student_id
JOIN applicants a ON a.id = st.applicant_id
JOIN users u ON u.id = a.user_id
WHERE ss.professor_id = current_actor_id();
GRANT SELECT ON professor_class_lists TO authenticated;
