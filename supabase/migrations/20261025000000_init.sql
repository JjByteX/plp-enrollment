CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "citext" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "extensions";

GRANT USAGE ON SCHEMA public TO authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated, service_role;

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
    college_id      uuid NULL REFERENCES colleges (id),
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_college_required CHECK (role NOT IN ('dean','college_secretary') OR college_id IS NOT NULL)
);
CREATE INDEX idx_users_role ON users (role);
CREATE INDEX idx_users_college ON users (college_id);
COMMENT ON COLUMN users.role IS 'admin has every permission of every other role per enrollment-plan.md Decided section';
COMMENT ON COLUMN users.college_id IS 'Deans and College Secretaries are limited to one college (enrollment-plan.md Access table)';

CREATE TABLE programs (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        varchar(20) NOT NULL UNIQUE,
    name        varchar(150) NOT NULL,
    college_id  uuid NOT NULL REFERENCES colleges (id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE program_payment_settings (
    program_id        uuid PRIMARY KEY REFERENCES programs (id) ON DELETE CASCADE,
    payment_required  boolean NOT NULL DEFAULT false,
    updated_by        uuid NULL REFERENCES users (id),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE program_payment_settings IS 'Per-course payment toggle. Admin and Finance can change it; Registrar and Dean can see it but not change it. Every change is audit-logged.';

CREATE TABLE applicants (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                   uuid NOT NULL UNIQUE REFERENCES users (id),
    applicant_ref             varchar(40) NOT NULL UNIQUE,
    program_id                uuid NOT NULL REFERENCES programs (id),
    admission_date            date NOT NULL,
    admission_type            text NOT NULL CHECK (admission_type IN ('new','transferee','foreign')),
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    admissions_verified_docs  text[] NOT NULL DEFAULT '{}',

    withdrawn_at              timestamptz NULL,
    withdrawn_by              uuid NULL,
    withdrawn_reason          text NULL,
    CONSTRAINT applicants_withdrawn_together CHECK (
        (withdrawn_at IS NULL AND withdrawn_by IS NULL AND withdrawn_reason IS NULL)
        OR (withdrawn_at IS NOT NULL AND withdrawn_by IS NOT NULL AND withdrawn_reason IS NOT NULL)),
    CONSTRAINT applicants_withdrawn_reason_length CHECK (length(withdrawn_reason) <= 500)
);
CREATE INDEX idx_applicants_program ON applicants (program_id);
CREATE INDEX idx_applicants_withdrawn ON applicants (withdrawn_at DESC) WHERE withdrawn_at IS NOT NULL;
COMMENT ON COLUMN applicants.admissions_verified_docs IS 'doc_type slugs Admissions approved before the handoff. Shown to the Registrar as "Verified in Admissions"; never ticks a document.';

CREATE TABLE admissions_intake_log (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_ref           varchar(40) NOT NULL,
    full_name               varchar(150) NOT NULL,
    email                   citext NOT NULL,
    program_code            varchar(20) NOT NULL,
    admission_date          date NOT NULL,
    admission_type          text NOT NULL CHECK (admission_type IN ('new','transferee','foreign')),
    source_name             varchar(60) NOT NULL DEFAULT 'PLP Admissions',
    received_at             timestamptz NOT NULL DEFAULT now(),
    status                  text NOT NULL CHECK (status IN ('accepted','rejected')),
    rejection_reason        text NULL,
    raw_payload             jsonb NOT NULL,
    resulting_applicant_id  uuid NULL,
    CONSTRAINT fk_intake_applicant FOREIGN KEY (resulting_applicant_id) REFERENCES applicants (id)
);
CREATE INDEX idx_intake_ref ON admissions_intake_log (applicant_ref);
CREATE INDEX idx_intake_status ON admissions_intake_log (status);
COMMENT ON TABLE admissions_intake_log IS 'Every request received from Admissions, successful or failed, with who sent it and when. Admin can view all of these, resend a failed one, and toggle the connection on/off.';

CREATE TABLE admissions_connection_settings (
    id          boolean PRIMARY KEY DEFAULT true CHECK (id),
    is_enabled  boolean NOT NULL DEFAULT true,
    updated_by  uuid NULL REFERENCES users (id),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO admissions_connection_settings (id, is_enabled) VALUES (true, true);

CREATE TABLE admissions_status_queue (
    student_id       uuid PRIMARY KEY,
    stage_sent       text NULL CHECK (stage_sent IN ('student','enrolled')),
    attempts         integer NOT NULL DEFAULT 0,
    last_attempt_at  timestamptz NULL,
    last_error       text NULL,
    updated_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE admissions_status_queue IS 'Last stage Admissions accepted for each student, with failed attempts. Read by the catch-up that re-sends missed status updates.';

CREATE TABLE student_number_counters (
    year         smallint PRIMARY KEY,
    last_number  integer NOT NULL
);

CREATE TABLE students (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id            uuid NOT NULL UNIQUE REFERENCES applicants (id),
    student_number          varchar(20) NOT NULL UNIQUE,
    documents_received_at   timestamptz NOT NULL DEFAULT now(),
    documents_received_by   uuid NOT NULL REFERENCES users (id),
    created_at              timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE admissions_status_queue
    ADD CONSTRAINT admissions_status_queue_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE;

CREATE TABLE document_requirements (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_type    text NOT NULL UNIQUE,
    label       varchar(200) NOT NULL,
    applies_to  text[] NOT NULL
                CHECK (cardinality(applies_to) > 0 AND applies_to <@ ARRAY['new','transferee','foreign']::text[]),
    required    boolean NOT NULL DEFAULT true,
    sort_order  integer NOT NULL DEFAULT 0,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE document_requirements IS 'What each admission type brings to the Registrar. required = false is a late item: it never blocks promotion and stays tickable after it (Form 137).';

CREATE TABLE documents (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id  uuid NOT NULL REFERENCES applicants (id),
    doc_type      text NOT NULL REFERENCES document_requirements (doc_type),
    created_at    timestamptz NOT NULL DEFAULT now(),
    received_at   timestamptz NOT NULL DEFAULT now(),
    received_by   uuid NOT NULL REFERENCES users (id),
    note          varchar(200) NULL,
    CONSTRAINT documents_applicant_doc_type_key UNIQUE (applicant_id, doc_type),
    CONSTRAINT documents_other_needs_note CHECK (doc_type <> 'other' OR nullif(trim(note), '') IS NOT NULL)
);

CREATE TABLE visit_slots (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id     uuid NOT NULL REFERENCES programs (id),
    slot_date      date NOT NULL,
    start_time     time NOT NULL,
    end_time       time NOT NULL,
    capacity       integer NOT NULL CHECK (capacity > 0),
    office_name    varchar(100) NOT NULL,
    status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','cancelled')),
    created_by     uuid NULL REFERENCES users (id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    what_to_bring  text NULL,
    CONSTRAINT visit_slots_time_order CHECK (end_time > start_time),
    CONSTRAINT visit_slots_unique UNIQUE (program_id, slot_date, start_time, office_name)
);
CREATE INDEX idx_visit_slots_lookup ON visit_slots (program_id, slot_date, start_time) WHERE status = 'open';
COMMENT ON COLUMN visit_slots.what_to_bring IS 'Optional notes for this slot. They follow the document checklist of the applicant''s admission type on the "Your next step" card and in the notification.';

CREATE TABLE visit_bookings (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slot_id       uuid NOT NULL REFERENCES visit_slots (id),
    applicant_id  uuid NOT NULL UNIQUE REFERENCES applicants (id),
    status        text NOT NULL DEFAULT 'booked' CHECK (status IN ('booked','attended','no_show')),
    assigned_by   uuid NULL REFERENCES users (id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_visit_bookings_slot ON visit_bookings (slot_id);

CREATE TABLE subjects (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id         uuid NOT NULL REFERENCES programs (id),
    code               varchar(30) NOT NULL,
    title              varchar(200) NOT NULL,
    units              numeric(3,1) NOT NULL CHECK (units >= 0),
    year_level         smallint NULL,
    has_laboratory     boolean NOT NULL DEFAULT false,
    semester           text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    offered_in_summer  boolean NOT NULL DEFAULT false,
    UNIQUE (program_id, code),
    CONSTRAINT subjects_summer_flag CHECK (NOT (semester = 'summer' AND offered_in_summer))
);
COMMENT ON COLUMN subjects.has_laboratory IS 'The subject also meets for a laboratory; sections get a second, unit-less row for it.';
COMMENT ON COLUMN subjects.semester IS 'The term a regular student takes the subject: 1st, 2nd or summer. A subject added without one takes the current term''s semester.';
COMMENT ON COLUMN subjects.offered_in_summer IS 'The subject also runs in summer terms (retakes). Not set for a summer-only subject.';

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
    capacity         integer NOT NULL CHECK (capacity > 0),
    rejected_reason  text NULL,
    rejected_by      uuid NULL REFERENCES users (id),
    rejected_at      timestamptz NULL,
    school_year      text NOT NULL,
    semester         text NOT NULL,
    CONSTRAINT sections_school_year_format CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
    CONSTRAINT sections_semester_valid CHECK (semester IN ('1st','2nd','summer')),
    CONSTRAINT sections_term_name_key UNIQUE (program_id, year_level, name, school_year, semester)
);
CREATE INDEX idx_sections_term ON sections (school_year, semester);
COMMENT ON COLUMN sections.capacity IS 'Seats for automatic placement. A manual move by the Secretary or Dean may go over it.';
COMMENT ON COLUMN sections.rejected_reason IS 'Why the Dean or Registrar sent the schedule back to draft. Cleared when it is submitted again.';

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
    meeting       text NOT NULL DEFAULT 'lecture' CHECK (meeting IN ('lecture','laboratory')),
    CONSTRAINT section_subjects_unique_meeting UNIQUE (section_id, subject_id, meeting),
    CONSTRAINT section_subjects_time_pair CHECK (
        (start_time IS NULL AND end_time IS NULL AND day_of_week IS NULL)
        OR (start_time IS NOT NULL AND end_time IS NOT NULL AND day_of_week IS NOT NULL AND end_time > start_time)
    ),

    CONSTRAINT section_subjects_no_room_clash EXCLUDE USING gist
        (room_id WITH =, day_of_week WITH =, slot_range WITH &&)
        WHERE (room_id IS NOT NULL AND day_of_week IS NOT NULL),
    CONSTRAINT section_subjects_no_professor_clash EXCLUDE USING gist
        (professor_id WITH =, day_of_week WITH =, slot_range WITH &&)
        WHERE (professor_id IS NOT NULL AND day_of_week IS NOT NULL)
);
CREATE INDEX idx_section_subjects_professor ON section_subjects (professor_id);

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
COMMENT ON TABLE enrollment_term IS 'The current school year and semester. One row, Admin only, audit-logged. Admin sets it with: INSERT INTO enrollment_term (school_year, semester) VALUES (''2026-2027'', ''1st''); and later UPDATE enrollment_term SET school_year = ..., semester = ...';

CREATE TABLE student_sections (
    student_id   uuid NOT NULL REFERENCES students (id),
    section_id   uuid NOT NULL REFERENCES sections (id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    school_year  text NOT NULL,
    semester     text NOT NULL,
    PRIMARY KEY (student_id, school_year, semester)
);
CREATE INDEX idx_student_sections_section ON student_sections (section_id);
COMMENT ON TABLE student_sections IS 'The enrollment: one row per student per term, holding the section. The term is copied from the section.';

CREATE TABLE assessment_slips (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        uuid NOT NULL REFERENCES students (id),
    payment_required  boolean NOT NULL,
    issued_by         uuid NOT NULL REFERENCES users (id),
    issued_at         timestamptz NOT NULL DEFAULT now(),
    schedule          jsonb NOT NULL,
    school_year       text NOT NULL,
    semester          text NOT NULL,
    CONSTRAINT assessment_slips_school_year_format CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
    CONSTRAINT assessment_slips_semester_valid CHECK (semester IN ('1st','2nd','summer')),
    CONSTRAINT assessment_slips_student_term_key UNIQUE (student_id, school_year, semester)
);
COMMENT ON COLUMN assessment_slips.schedule IS 'The schedule as it was when the slip was issued. Never changes.';

CREATE TABLE payments (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES students (id),
    amount_due    numeric(12,2) NULL CHECK (amount_due >= 0),
    amount_paid   numeric(12,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    receipt_no    varchar(60) NULL,
    status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','cleared')),
    recorded_by   uuid NULL REFERENCES users (id),
    cleared_at    timestamptz NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    school_year   text NOT NULL,
    semester      text NOT NULL,
    CONSTRAINT payments_cleared_complete CHECK (
        status = 'pending'
        OR (amount_due IS NOT NULL AND amount_paid >= amount_due AND recorded_by IS NOT NULL AND cleared_at IS NOT NULL)
    ),
    CONSTRAINT payments_school_year_format CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
    CONSTRAINT payments_semester_valid CHECK (semester IN ('1st','2nd','summer')),
    CONSTRAINT payments_student_term_key UNIQUE (student_id, school_year, semester)
);

CREATE TABLE cors (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES students (id),
    issued_by    uuid NOT NULL REFERENCES users (id),
    issued_at    timestamptz NOT NULL DEFAULT now(),
    school_year  text NOT NULL CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
    semester     text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    schedule     jsonb NOT NULL,
    CONSTRAINT cors_student_term_key UNIQUE (student_id, school_year, semester)
);
COMMENT ON TABLE cors IS 'A row here means the student is enrolled for that term.';
COMMENT ON COLUMN cors.schedule IS 'The final schedule as it was when the COR was issued. Never changes.';

CREATE TABLE mass_reschedules (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    affected_date   date NOT NULL,
    program_id      uuid NULL REFERENCES programs (id),
    office_name     varchar(100) NULL,
    reason          text NOT NULL,
    target_slot_id  uuid NULL REFERENCES visit_slots (id),
    triggered_by    uuid NOT NULL REFERENCES users (id),
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reschedule_requests (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id     uuid NOT NULL REFERENCES visit_bookings (id),
    requested_by   uuid NOT NULL REFERENCES users (id),
    reason         text NOT NULL,
    status         text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','declined')),
    new_slot_id    uuid NULL REFERENCES visit_slots (id),
    decision_note  text NULL,
    decided_by     uuid NULL REFERENCES users (id),
    decided_at     timestamptz NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT reschedule_requests_decided CHECK (
        status = 'pending' OR (decided_by IS NOT NULL AND decided_at IS NOT NULL)
    )
);
CREATE UNIQUE INDEX uq_reschedule_one_pending ON reschedule_requests (booking_id) WHERE status = 'pending';

CREATE TABLE notifications (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES users (id),
    kind            text NOT NULL,
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

CREATE TABLE audit_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id    uuid NULL,
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

REVOKE UPDATE, DELETE, TRUNCATE ON audit_log FROM PUBLIC, authenticated, service_role;

CREATE TABLE grading_settings (
    id               boolean PRIMARY KEY DEFAULT true CHECK (id),
    inc_window_days  integer NOT NULL DEFAULT 14 CHECK (inc_window_days BETWEEN 1 AND 365),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
INSERT INTO grading_settings (id) VALUES (true);
COMMENT ON TABLE grading_settings IS 'One row. inc_window_days: how long an incomplete stays open after approval (charter default 14).';

CREATE TABLE grade_bands (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    label          varchar(30) NOT NULL,
    outcome        text NOT NULL CHECK (outcome IN ('passed','incomplete','failed','dropped')),
    is_descriptive boolean NOT NULL DEFAULT false,
    from_value     numeric(6,2) NULL,
    to_value       numeric(6,2) NULL,
    sort_order     integer NOT NULL DEFAULT 0,
    CONSTRAINT grade_bands_range_pair CHECK ((from_value IS NULL) = (to_value IS NULL)),
    CONSTRAINT grade_bands_range_order CHECK (from_value IS NULL OR from_value <= to_value),
    CONSTRAINT grade_bands_descriptive_passed CHECK (NOT is_descriptive OR outcome = 'passed')
);
CREATE UNIQUE INDEX grade_bands_label_key ON grade_bands (lower(label));
COMMENT ON TABLE grade_bands IS 'The grading scale. Descriptive bands (Excellent, Very Good ...) are display only and never change a rule.';

CREATE TABLE grade_sheets (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id    uuid NOT NULL REFERENCES sections (id) ON DELETE CASCADE,
    subject_id    uuid NOT NULL REFERENCES subjects (id),
    school_year   text NOT NULL,
    semester      text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','approved')),
    submitted_by  uuid NULL REFERENCES users (id),
    submitted_at  timestamptz NULL,
    approved_by   uuid NULL REFERENCES users (id),
    approved_at   timestamptz NULL,
    returned_reason text NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (section_id, subject_id)
);
COMMENT ON TABLE grade_sheets IS 'The grades of one subject in one section. draft (Professor edits), submitted (waits for the Dean), approved (locked).';

CREATE TABLE grades (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id      uuid NOT NULL REFERENCES grade_sheets (id) ON DELETE CASCADE,
    section_id    uuid NOT NULL REFERENCES sections (id) ON DELETE CASCADE,
    subject_id    uuid NOT NULL REFERENCES subjects (id),
    student_id    uuid NOT NULL REFERENCES students (id),
    school_year   text NOT NULL,
    semester      text NOT NULL,
    grade_text    text NOT NULL,
    outcome       text NOT NULL CHECK (outcome IN ('passed','incomplete','failed','dropped')),
    lapsed        boolean NOT NULL DEFAULT false,
    outcome_since timestamptz NOT NULL DEFAULT now(),
    entered_by    uuid NULL REFERENCES users (id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sheet_id, student_id)
);
CREATE INDEX idx_grades_student ON grades (student_id, school_year, semester);
COMMENT ON COLUMN grades.outcome IS 'Copied from the band when the grade was entered. A later change of the scale does not rewrite it.';
COMMENT ON COLUMN grades.outcome_since IS 'When the outcome took its present value (approval, a grade change, or a lapse). The INC window counts from here.';

CREATE TABLE grade_changes (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    grade_id         uuid NOT NULL REFERENCES grades (id) ON DELETE CASCADE,
    old_grade_text   text NOT NULL,
    old_outcome      text NOT NULL,
    new_grade_text   text NOT NULL,
    new_outcome      text NOT NULL,
    kind             text NOT NULL CHECK (kind IN ('correction','inc_completion','drop')),
    reason           text NOT NULL CHECK (length(btrim(reason)) > 0),
    status           text NOT NULL DEFAULT 'pending_dean'
                     CHECK (status IN ('pending_dean','pending_registrar','applied','rejected')),
    proposed_by      uuid NULL REFERENCES users (id),
    proposed_at      timestamptz NOT NULL DEFAULT now(),
    dean_by          uuid NULL REFERENCES users (id),
    dean_at          timestamptz NULL,
    registrar_by     uuid NULL REFERENCES users (id),
    registrar_at     timestamptz NULL,
    rejected_by      uuid NULL REFERENCES users (id),
    rejected_at      timestamptz NULL,
    rejected_reason  text NULL
);
CREATE UNIQUE INDEX grade_changes_one_open ON grade_changes (grade_id) WHERE status IN ('pending_dean','pending_registrar');
COMMENT ON TABLE grade_changes IS 'The only way to change an approved grade: Professor proposes, Dean signs, Registrar approves.';

CREATE TABLE subject_prerequisites (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id      uuid NOT NULL REFERENCES subjects (id),
    prerequisite_id uuid NOT NULL REFERENCES subjects (id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (subject_id, prerequisite_id),
    CONSTRAINT subject_prerequisites_not_self CHECK (subject_id <> prerequisite_id)
);
CREATE INDEX idx_subject_prerequisites_required ON subject_prerequisites (prerequisite_id);
COMMENT ON TABLE subject_prerequisites IS 'A subject needs every listed prerequisite passed (or credited) before a student may take it.';

CREATE TABLE student_credits (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid NOT NULL REFERENCES students (id),
    subject_id      uuid NOT NULL REFERENCES subjects (id),
    reason          text NOT NULL CHECK (length(btrim(reason)) > 0),
    status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
    recorded_by     uuid NULL REFERENCES users (id),
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    decided_by      uuid NULL REFERENCES users (id),
    decided_at      timestamptz NULL,
    rejected_reason text NULL
);

CREATE UNIQUE INDEX student_credits_one_live ON student_credits (student_id, subject_id) WHERE status IN ('pending','approved');
CREATE INDEX idx_student_credits_student ON student_credits (student_id);
COMMENT ON TABLE student_credits IS 'A subject credited to a transferee. Dean or Secretary records, Registrar approves. An approved credit counts as a pass.';

CREATE TABLE term_closures (
    school_year  text NOT NULL CHECK (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
    semester     text NOT NULL CHECK (semester IN ('1st','2nd','summer')),
    closed_by    uuid NULL REFERENCES users (id),
    closed_at    timestamptz NOT NULL DEFAULT now(),
    opened_at    timestamptz NULL,
    PRIMARY KEY (school_year, semester)
);
COMMENT ON TABLE term_closures IS 'A closed term. opened_at is set once the next regular term has opened and its students were promoted.';

CREATE TABLE term_results (
    school_year  text NOT NULL,
    semester     text NOT NULL,
    student_id   uuid NOT NULL REFERENCES students (id),
    program_id   uuid NOT NULL REFERENCES programs (id),
    year_level   smallint NOT NULL,
    section_name varchar(50) NOT NULL,
    result       text NOT NULL CHECK (result IN ('promote','review','completed')),
    reason       text NULL,
    placed_at    timestamptz NULL,
    PRIMARY KEY (school_year, semester, student_id),
    FOREIGN KEY (school_year, semester) REFERENCES term_closures (school_year, semester)
);
CREATE INDEX idx_term_results_student ON term_results (student_id);
COMMENT ON TABLE term_results IS 'What closing a term decided for each enrolled student: promote, review (with the reason) or completed.';
COMMENT ON COLUMN term_results.placed_at IS 'When a promoted student was seated in the next term''s section.';

CREATE TABLE student_subjects (
    student_id          uuid NOT NULL,
    school_year         text NOT NULL,
    semester            text NOT NULL,
    section_subject_id  uuid NOT NULL REFERENCES section_subjects (id) ON DELETE CASCADE,
    source              text NOT NULL CHECK (source IN ('section','added')),
    added_by            uuid NULL REFERENCES users (id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (student_id, school_year, semester, section_subject_id),
    FOREIGN KEY (student_id, school_year, semester)
        REFERENCES student_sections (student_id, school_year, semester) ON DELETE CASCADE
);
CREATE INDEX idx_student_subjects_section_subject ON student_subjects (section_subject_id);
COMMENT ON TABLE student_subjects IS 'The subject list of one enrollment: one row per meeting of a section subject the student takes. source section = copied from the student''s section, added = a retake or back subject.';

CREATE TABLE leaves (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL REFERENCES students (id),
    start_year       text NOT NULL CHECK (start_year ~ '^[0-9]{4}-[0-9]{4}$'),
    start_semester   text NOT NULL CHECK (start_semester IN ('1st','2nd')),
    terms            smallint NOT NULL CHECK (terms IN (1, 2)),
    return_year      text NOT NULL CHECK (return_year ~ '^[0-9]{4}-[0-9]{4}$'),
    return_semester  text NOT NULL CHECK (return_semester IN ('1st','2nd')),
    reason           text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
    status           text NOT NULL DEFAULT 'requested'
                     CHECK (status IN ('requested','approved','active','ended','rejected')),
    recorded_by      uuid NULL REFERENCES users (id),
    recorded_at      timestamptz NOT NULL DEFAULT now(),
    decided_by       uuid NULL REFERENCES users (id),
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    activated_at     timestamptz NULL,
    ended_at         timestamptz NULL,
    returned_at      timestamptz NULL,
    returned_year    text NULL,
    returned_semester text NULL,
    readmitted_by    uuid NULL REFERENCES users (id)
);
CREATE INDEX idx_leaves_student ON leaves (student_id);

CREATE UNIQUE INDEX leaves_one_open ON leaves (student_id)
    WHERE status IN ('requested','approved','active') OR (status = 'ended' AND returned_at IS NULL);
COMMENT ON TABLE leaves IS 'A leave of absence. Staff record it, the Dean approves, the system activates and ends it. returned_at is set when the student is placed in a section again.';

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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

CREATE OR REPLACE FUNCTION my_applicant_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.id FROM applicants a WHERE a.user_id = current_actor_id()
$$;

CREATE OR REPLACE FUNCTION my_student_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id FROM students s JOIN applicants a ON a.id = s.applicant_id WHERE a.user_id = current_actor_id()
$$;

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

CREATE OR REPLACE FUNCTION semester_rank(p_semester text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester WHEN '1st' THEN 1 WHEN '2nd' THEN 2 WHEN 'summer' THEN 3 END
$$;

CREATE OR REPLACE FUNCTION subject_in_term(p_subject_semester text, p_offered_in_summer boolean, p_term_semester text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_subject_semester = p_term_semester OR (p_term_semester = 'summer' AND coalesce(p_offered_in_summer, false))
$$;

CREATE OR REPLACE FUNCTION term_order(p_year text, p_semester text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT left(p_year, 4)::integer * 4 + semester_rank(p_semester)
$$;

CREATE OR REPLACE FUNCTION next_regular_term(p_year text, p_semester text)
RETURNS TABLE (next_year text, next_semester text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester
           WHEN '1st' THEN p_year
           ELSE (left(p_year, 4)::integer + 1)::text || '-' || (left(p_year, 4)::integer + 2)::text
         END,
         CASE p_semester WHEN '1st' THEN '2nd' ELSE '1st' END
   WHERE p_semester IN ('1st','2nd') AND p_year ~ '^[0-9]{4}-[0-9]{4}$'
$$;

CREATE OR REPLACE FUNCTION previous_regular_term(p_year text, p_semester text)
RETURNS TABLE (prev_year text, prev_semester text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester
           WHEN '2nd' THEN p_year
           ELSE (left(p_year, 4)::integer - 1)::text || '-' || left(p_year, 4)
         END,
         CASE p_semester WHEN '2nd' THEN '1st' ELSE '2nd' END
   WHERE p_semester IN ('1st','2nd') AND p_year ~ '^[0-9]{4}-[0-9]{4}$'
$$;

CREATE OR REPLACE FUNCTION leave_return_term(p_year text, p_semester text, p_terms integer)
RETURNS TABLE (return_year text, return_semester text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_year text := p_year;
  v_sem  text := p_semester;
  i      integer;
BEGIN
  FOR i IN 1..p_terms LOOP
    SELECT n.next_year, n.next_semester INTO v_year, v_sem FROM next_regular_term(v_year, v_sem) n;
  END LOOP;
  RETURN QUERY SELECT v_year, v_sem;
END;
$$;

CREATE OR REPLACE FUNCTION leave_covers_term(
  p_start_year text, p_start_semester text, p_return_year text, p_return_semester text,
  p_year text, p_semester text
) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT term_order(p_year, p_semester) >= term_order(p_start_year, p_start_semester)
     AND term_order(p_year, p_semester) <  term_order(p_return_year, p_return_semester)
$$;

CREATE OR REPLACE FUNCTION term_text(p_year text, p_semester text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_semester WHEN 'summer' THEN 'summer' ELSE p_semester || ' semester' END || ' of school year ' || p_year
$$;

CREATE OR REPLACE FUNCTION current_term() RETURNS TABLE (school_year text, semester text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.school_year, t.semester FROM enrollment_term t
$$;

CREATE OR REPLACE FUNCTION student_enrollment(p_student uuid) RETURNS SETOF student_sections
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT ss.*
    FROM student_sections ss
   WHERE ss.student_id = p_student
   ORDER BY EXISTS (SELECT 1 FROM enrollment_term t
                     WHERE t.school_year = ss.school_year AND t.semester = ss.semester) DESC,
            ss.school_year DESC,
            semester_rank(ss.semester) DESC
   LIMIT 1
$$;

CREATE OR REPLACE FUNCTION my_section_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT e.section_id FROM student_enrollment(my_student_id()) e
$$;

CREATE OR REPLACE FUNCTION my_visit_slot_ids() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT vb.slot_id FROM visit_bookings vb WHERE vb.applicant_id = my_applicant_id()
$$;

CREATE OR REPLACE FUNCTION audit_log_append_only() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append only';
END;
$$ LANGUAGE plpgsql;

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

CREATE OR REPLACE FUNCTION create_program_payment_setting() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO program_payment_settings (program_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION stamp_payment_setting() RETURNS trigger AS $$
BEGIN
  NEW.updated_by = current_actor_id();
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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

CREATE OR REPLACE FUNCTION flip_user_to_student() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE users SET role = 'student'
  WHERE id = (SELECT a.user_id FROM applicants a WHERE a.id = NEW.applicant_id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION prevent_student_number_edit() RETURNS trigger AS $$
BEGIN
  IF NEW.student_number IS DISTINCT FROM OLD.student_number THEN
    RAISE EXCEPTION 'student_number cannot be changed once assigned';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_booking_capacity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slot visit_slots%ROWTYPE;
  v_program uuid;
  v_taken integer;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.slot_id = OLD.slot_id THEN
    RETURN NEW;
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

CREATE OR REPLACE FUNCTION enforce_slot_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booked integer;
BEGIN
  SELECT count(*) INTO v_booked FROM visit_bookings WHERE slot_id = NEW.id;

  IF NEW.capacity < v_booked THEN
    RAISE EXCEPTION 'Capacity cannot be lower than the % applicant(s) already booked', v_booked;
  END IF;

  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' AND v_booked > 0 THEN
    RAISE EXCEPTION 'A slot with bookings cannot be cancelled. Close it, then move the applicants';
  END IF;

  IF NEW.program_id IS DISTINCT FROM OLD.program_id AND v_booked > 0 THEN
    RAISE EXCEPTION 'The program of a slot with bookings cannot be changed';
  END IF;

  IF v_booked > 0 AND (
       NEW.slot_date   IS DISTINCT FROM OLD.slot_date
    OR NEW.start_time  IS DISTINCT FROM OLD.start_time
    OR NEW.end_time    IS DISTINCT FROM OLD.end_time
    OR NEW.office_name IS DISTINCT FROM OLD.office_name
  ) THEN
    RAISE EXCEPTION 'The date, time and office of a slot with bookings cannot be changed. Close it and move the applicants';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION next_open_slot(
  p_program uuid, p_exclude_date date DEFAULT NULL, p_exclude_office text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slot uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can look up visit slots';
  END IF;

  SELECT s.id INTO v_slot
  FROM visit_slots s
  WHERE s.program_id = p_program
    AND s.status = 'open'
    AND (s.slot_date + s.end_time) > (now() AT TIME ZONE 'Asia/Manila')
    AND s.capacity > (SELECT count(*) FROM visit_bookings b WHERE b.slot_id = s.id)
    AND NOT (p_exclude_date IS NOT NULL AND s.slot_date = p_exclude_date
             AND (p_exclude_office IS NULL OR s.office_name = p_exclude_office))
  ORDER BY s.slot_date, s.start_time, s.office_name
  LIMIT 1;

  RETURN v_slot;
END;
$$;

CREATE OR REPLACE FUNCTION assign_visit_slot_core(p_applicant uuid, p_slot uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user       uuid;
  v_type       text;
  v_slot       visit_slots%ROWTYPE;
  v_booking    visit_bookings%ROWTYPE;
  v_booking_id uuid;
  v_kind       text;
  v_title      text;
  v_window     text;
  v_when       text;
  v_bring      text;
BEGIN
  SELECT user_id, admission_type INTO v_user, v_type FROM applicants WHERE id = p_applicant;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
  END IF;
  IF EXISTS (SELECT 1 FROM applicants WHERE id = p_applicant AND withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This applicant has withdrawn';
  END IF;

  SELECT * INTO v_slot FROM visit_slots WHERE id = p_slot;
  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'Visit slot not found';
  END IF;

  IF nullif(trim(p_reason), '') IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', trim(p_reason), true);
  END IF;

  SELECT * INTO v_booking FROM visit_bookings WHERE applicant_id = p_applicant FOR UPDATE;

  IF v_booking.id IS NULL THEN
    INSERT INTO visit_bookings (slot_id, applicant_id, assigned_by)
    VALUES (p_slot, p_applicant, current_actor_id())
    RETURNING id INTO v_booking_id;
    v_kind  := 'visit_assigned';
    v_title := 'Your visit date';
  ELSE
    IF v_booking.slot_id = p_slot THEN
      RAISE EXCEPTION 'This applicant is already booked into this slot';
    END IF;
    IF v_booking.status <> 'booked' THEN
      RAISE EXCEPTION 'This visit is already marked %, so it cannot be moved', v_booking.status;
    END IF;
    UPDATE visit_bookings
       SET slot_id = p_slot, assigned_by = current_actor_id()
     WHERE id = v_booking.id;
    v_booking_id := v_booking.id;
    v_kind  := 'visit_moved';
    v_title := 'Your visit has been moved';
  END IF;

  v_window := to_char(timestamp '2000-01-01' + v_slot.start_time, 'FMHH12:MI AM')
              || ' to ' ||
              to_char(timestamp '2000-01-01' + v_slot.end_time, 'FMHH12:MI AM');
  v_when   := to_char(v_slot.slot_date, 'FMDay, FMMonth FMDD, YYYY');

  v_bring := document_checklist_text(v_type);
  IF nullif(trim(v_slot.what_to_bring), '') IS NOT NULL THEN
    v_bring := CASE WHEN v_bring IS NULL THEN trim(v_slot.what_to_bring)
                    ELSE v_bring || E'\n\n' || trim(v_slot.what_to_bring) END;
  END IF;

  INSERT INTO notifications (user_id, kind, title, message, office_name, window_label, scheduled_for, what_to_bring)
  VALUES (
    v_user, v_kind, v_title,
    'Please go to ' || v_slot.office_name || ' on ' || v_when || ', ' || v_window || '.',
    v_slot.office_name,
    v_window,
    (v_slot.slot_date + v_slot.start_time) AT TIME ZONE 'Asia/Manila',
    v_bring
  );

  IF nullif(trim(p_reason), '') IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;

  RETURN v_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION assign_visit_slot(p_applicant uuid, p_slot uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can assign visits';
  END IF;
  RETURN assign_visit_slot_core(p_applicant, p_slot, p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION auto_assign_visit(p_applicant uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program   uuid;
  v_slot      visit_slots%ROWTYPE;
  v_candidate uuid;
BEGIN
  SELECT program_id INTO v_program FROM applicants WHERE id = p_applicant AND withdrawn_at IS NULL;
  IF v_program IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM students WHERE applicant_id = p_applicant) THEN
    RETURN NULL;
  END IF;

  SELECT s.* INTO v_slot
    FROM visit_bookings b JOIN visit_slots s ON s.id = b.slot_id
   WHERE b.applicant_id = p_applicant;

  IF v_slot.id IS NULL THEN
    FOR v_candidate IN
      SELECT s.id
        FROM visit_slots s
       WHERE s.program_id = v_program
         AND s.status = 'open'
         AND (s.slot_date + s.end_time) > (now() AT TIME ZONE 'Asia/Manila')
         AND s.capacity > (SELECT count(*) FROM visit_bookings b WHERE b.slot_id = s.id)
       ORDER BY s.slot_date, s.start_time, s.office_name
       LIMIT 5
    LOOP
      BEGIN
        PERFORM assign_visit_slot_core(p_applicant, v_candidate);
        SELECT * INTO v_slot FROM visit_slots WHERE id = v_candidate;
        EXIT;
      EXCEPTION WHEN raise_exception OR unique_violation THEN
        NULL;
      END;
    END LOOP;
  END IF;

  IF v_slot.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'date',        to_char(v_slot.slot_date, 'YYYY-MM-DD'),
    'start_time',  to_char(v_slot.start_time, 'HH24:MI'),
    'end_time',    to_char(v_slot.end_time, 'HH24:MI'),
    'office_name', v_slot.office_name
  );
END;
$$;

CREATE OR REPLACE FUNCTION assign_unassigned_visits(p_program uuid, OUT assigned integer, OUT left_over integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r      record;
  v_slot uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can assign visits';
  END IF;

  assigned := 0;

  FOR r IN
    SELECT a.id
    FROM applicants a
    WHERE a.program_id = p_program
      AND NOT EXISTS (SELECT 1 FROM visit_bookings b WHERE b.applicant_id = a.id)
      AND NOT EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = a.id)
      AND a.withdrawn_at IS NULL
    ORDER BY a.admission_date, a.created_at, a.id
  LOOP
    v_slot := next_open_slot(p_program);
    EXIT WHEN v_slot IS NULL;
    PERFORM assign_visit_slot(r.id, v_slot);
    assigned := assigned + 1;
  END LOOP;

  SELECT count(*)::integer INTO left_over
  FROM applicants a
  WHERE a.program_id = p_program
    AND NOT EXISTS (SELECT 1 FROM visit_bookings b WHERE b.applicant_id = a.id)
    AND NOT EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = a.id)
    AND a.withdrawn_at IS NULL;
END;
$$;

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

CREATE OR REPLACE FUNCTION mass_reschedule(
  p_date date, p_program uuid, p_office text, p_reason text, OUT moved integer, OUT left_over integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_office text := nullif(btrim(coalesce(p_office, '')), '');
  r        record;
  v_slot   uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can set a mass reschedule';
  END IF;
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'Choose the affected date';
  END IF;
  IF p_date < (now() AT TIME ZONE 'Asia/Manila')::date THEN
    RAISE EXCEPTION 'The affected date cannot be in the past';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM visit_bookings b JOIN visit_slots s ON s.id = b.slot_id
     WHERE b.status = 'booked' AND s.slot_date = p_date
       AND (p_program IS NULL OR s.program_id = p_program)
       AND (v_office IS NULL OR s.office_name = v_office)
  ) THEN
    RAISE EXCEPTION 'No booked visit falls on that date';
  END IF;

  INSERT INTO mass_reschedules (affected_date, program_id, office_name, reason)
  VALUES (p_date, p_program, v_office, v_reason);

  moved := 0;
  left_over := 0;
  FOR r IN
    SELECT b.applicant_id, a.program_id
      FROM visit_bookings b
      JOIN visit_slots s ON s.id = b.slot_id
      JOIN applicants a ON a.id = b.applicant_id
     WHERE b.status = 'booked' AND s.slot_date = p_date
       AND (p_program IS NULL OR s.program_id = p_program)
       AND (v_office IS NULL OR s.office_name = v_office)
     ORDER BY s.start_time, a.admission_date, a.created_at, a.id
  LOOP
    v_slot := next_open_slot(r.program_id, p_date, v_office);
    IF v_slot IS NULL THEN
      left_over := left_over + 1;
      CONTINUE;
    END IF;

    PERFORM assign_visit_slot(r.applicant_id, v_slot, 'Mass reschedule: ' || v_reason);
    moved := moved + 1;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION request_reschedule(p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_booking visit_bookings%ROWTYPE;
  v_id      uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('applicant','student') THEN
    RAISE EXCEPTION 'Only an applicant or student can request a reschedule';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  SELECT * INTO v_booking FROM visit_bookings WHERE applicant_id = my_applicant_id() FOR UPDATE;
  IF NOT FOUND OR v_booking.status <> 'booked' THEN
    RAISE EXCEPTION 'You have no booked visit to reschedule';
  END IF;
  IF EXISTS (SELECT 1 FROM reschedule_requests WHERE booking_id = v_booking.id AND status = 'pending') THEN
    RAISE EXCEPTION 'You already have a reschedule request waiting for the Registrar';
  END IF;

  INSERT INTO reschedule_requests (booking_id, requested_by, reason)
  VALUES (v_booking.id, current_actor_id(), v_reason)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION decide_reschedule(
  p_request uuid, p_approve boolean, p_slot uuid, p_note text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_note    text := nullif(btrim(coalesce(p_note, '')), '');
  v_req     reschedule_requests%ROWTYPE;
  v_booking visit_bookings%ROWTYPE;
  v_program uuid;
  v_user    uuid;
  v_current date;
  v_slot    uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can approve or decline a reschedule request';
  END IF;
  IF p_approve IS NULL THEN
    RAISE EXCEPTION 'Approve or decline the request';
  END IF;
  IF v_note IS NOT NULL AND length(v_note) > 500 THEN
    RAISE EXCEPTION 'The note is longer than 500 characters';
  END IF;

  SELECT * INTO v_req FROM reschedule_requests WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'This request has already been decided';
  END IF;

  SELECT * INTO v_booking FROM visit_bookings WHERE id = v_req.booking_id FOR UPDATE;
  SELECT a.program_id, a.user_id INTO v_program, v_user FROM applicants a WHERE a.id = v_booking.applicant_id;

  IF p_approve THEN
    IF v_booking.status <> 'booked' THEN
      RAISE EXCEPTION 'This visit is already marked %, so it cannot be moved', v_booking.status;
    END IF;
    v_slot := p_slot;
    IF v_slot IS NULL THEN
      SELECT slot_date INTO v_current FROM visit_slots WHERE id = v_booking.slot_id;
      v_slot := next_open_slot(v_program, v_current);
      IF v_slot IS NULL THEN
        RAISE EXCEPTION 'No open slot with a free seat is available. Add a slot for this program or choose one';
      END IF;
    END IF;
    PERFORM assign_visit_slot(
      v_booking.applicant_id, v_slot,
      'Reschedule request approved' || coalesce(': ' || v_note, '')
    );

    UPDATE reschedule_requests
       SET status = 'approved', new_slot_id = v_slot, decision_note = v_note
     WHERE id = v_req.id;
  ELSE
    IF v_note IS NULL THEN
      RAISE EXCEPTION 'Enter the reason for declining';
    END IF;
    UPDATE reschedule_requests
       SET status = 'declined', decision_note = v_note
     WHERE id = v_req.id;
    INSERT INTO notifications (user_id, kind, title, message)
    VALUES (
      v_user, 'reschedule_declined', 'Your reschedule request was declined',
      'The Registrar declined your request: ' || v_note || ' Your visit date stays the same.'
    );
  END IF;

  RETURN v_req.id;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_documents_open() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_doc  documents%ROWTYPE;
  v_req  document_requirements%ROWTYPE;
  v_type text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_doc := OLD;
  ELSE
    v_doc := NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND (NEW.applicant_id IS DISTINCT FROM OLD.applicant_id
                           OR NEW.doc_type IS DISTINCT FROM OLD.doc_type) THEN
    RAISE EXCEPTION 'The applicant and the document type of a received document cannot be changed';
  END IF;

  SELECT * INTO v_req FROM document_requirements WHERE doc_type = v_doc.doc_type;
  SELECT admission_type INTO v_type FROM applicants WHERE id = v_doc.applicant_id;

  IF TG_OP = 'INSERT' THEN
    IF NOT v_req.active THEN
      RAISE EXCEPTION 'This document is no longer on the checklist';
    END IF;
    IF v_type IS NULL OR NOT (v_type = ANY (v_req.applies_to)) THEN
      RAISE EXCEPTION 'This document does not apply to this applicant''s admission type';
    END IF;
  END IF;

  IF v_req.required AND EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = v_doc.applicant_id) THEN
    RAISE EXCEPTION 'This applicant is already a student, so required documents are locked. Ask an Admin to correct it';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.received_by := current_actor_id();
    NEW.received_at := now();
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.received_by := OLD.received_by;
    NEW.received_at := OLD.received_at;
    RETURN NEW;
  END IF;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION document_checklist_text(p_admission_type text) RETURNS text
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN count(*) = 0 THEN NULL
    ELSE 'Bring these documents:' || E'\n' ||
         string_agg(t.n || '. ' || t.label || CASE WHEN t.required THEN '' ELSE ' (can be submitted later)' END,
                    E'\n' ORDER BY t.n)
    END
  FROM (
    SELECT row_number() OVER (ORDER BY r.required DESC, r.sort_order, r.doc_type) AS n, r.label, r.required
    FROM document_requirements r
    WHERE r.active
      AND r.doc_type <> 'other'
      AND p_admission_type = ANY (r.applies_to)
  ) t
$$;

CREATE OR REPLACE FUNCTION mark_documents_received(p_applicant uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_app     applicants%ROWTYPE;
  v_missing text;
  v_late    text;
  v_student uuid;
  v_number  varchar;
  v_message text;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can mark documents received';
  END IF;

  SELECT * INTO v_app FROM applicants WHERE id = p_applicant FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
  END IF;

  IF v_app.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'This applicant has withdrawn';
  END IF;

  IF EXISTS (SELECT 1 FROM students s WHERE s.applicant_id = v_app.id) THEN
    RAISE EXCEPTION 'This applicant is already a student';
  END IF;

  SELECT string_agg(r.label, '; ' ORDER BY r.sort_order) INTO v_missing
  FROM document_requirements r
  WHERE r.active AND r.required
    AND v_app.admission_type = ANY (r.applies_to)
    AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.applicant_id = v_app.id AND d.doc_type = r.doc_type);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot mark documents received. Still missing: %', v_missing;
  END IF;

  SELECT string_agg(r.label, '; ' ORDER BY r.sort_order) INTO v_late
  FROM document_requirements r
  WHERE r.active AND NOT r.required
    AND r.doc_type <> 'other'
    AND v_app.admission_type = ANY (r.applies_to)
    AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.applicant_id = v_app.id AND d.doc_type = r.doc_type);

  INSERT INTO students (applicant_id, documents_received_by)
  VALUES (v_app.id, current_actor_id())
  RETURNING id, student_number INTO v_student, v_number;

  UPDATE visit_bookings SET status = 'attended'
   WHERE applicant_id = v_app.id AND status = 'booked';

  v_message := 'Your documents were received. Your student number is ' || v_number || '.';
  IF v_late IS NOT NULL THEN
    v_message := v_message || ' Still to submit later: ' || v_late || '.';
  END IF;

  INSERT INTO notifications (user_id, kind, title, message, email_status)
  VALUES (v_app.user_id, 'documents_received', 'Documents received', v_message, 'pending');

  RETURN v_student;
END;
$$;

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

CREATE OR REPLACE FUNCTION set_subject_semester() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.semester IS NULL THEN
    SELECT t.semester INTO NEW.semester FROM enrollment_term t;
    NEW.semester := coalesce(NEW.semester, '1st');
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION set_section_term() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_last text;
BEGIN
  IF NEW.school_year IS NULL OR NEW.semester IS NULL THEN
    SELECT t.school_year, t.semester INTO NEW.school_year, NEW.semester FROM enrollment_term t;
    IF NEW.school_year IS NULL THEN
      RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them before creating a section';
    END IF;
  END IF;

  IF NEW.name IS NULL OR btrim(NEW.name) = '' THEN
    PERFORM pg_advisory_xact_lock(hashtext(NEW.program_id::text || '/' || NEW.year_level || '/' || NEW.school_year || '/' || NEW.semester));
    SELECT max(s.name) INTO v_last FROM sections s
     WHERE s.program_id = NEW.program_id AND s.year_level = NEW.year_level
       AND s.school_year = NEW.school_year AND s.semester = NEW.semester
       AND s.name ~ '^[A-Z]$';
    IF v_last = 'Z' THEN
      RAISE EXCEPTION 'This year level already has sections A to Z';
    END IF;
    NEW.name := CASE WHEN v_last IS NULL THEN 'A' ELSE chr(ascii(v_last) + 1) END;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION set_enrollment_term() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_year text;
  v_sem  text;
BEGIN
  SELECT sec.school_year, sec.semester INTO v_year, v_sem FROM sections sec WHERE sec.id = NEW.section_id;
  IF TG_OP = 'UPDATE' AND (v_year, v_sem) IS DISTINCT FROM (OLD.school_year, OLD.semester) THEN
    RAISE EXCEPTION 'A student cannot be moved to a section of another term';
  END IF;
  NEW.school_year := v_year;
  NEW.semester := v_sem;
  RETURN NEW;
END;
$$;

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
  IF NEW.school_year IS DISTINCT FROM OLD.school_year OR NEW.semester IS DISTINCT FROM OLD.semester THEN
    RAISE EXCEPTION 'The term of a section cannot be changed';
  END IF;

  IF NEW.schedule_status = OLD.schedule_status THEN

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

    NEW.dean_signed_by := NULL;
    NEW.dean_signed_at := NULL;
  ELSE
    RAISE EXCEPTION 'Invalid schedule status change: % to %', OLD.schedule_status, NEW.schedule_status;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_section_subject_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_section uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.section_id ELSE NEW.section_id END;
  v_status  text;
  v_program uuid;
  v_college uuid;
  v_amend   boolean := coalesce(current_setting('app.amend_schedule', true), '') = 'on';
BEGIN
  SELECT s.schedule_status, s.program_id, p.college_id
    INTO v_status, v_program, v_college
    FROM sections s JOIN programs p ON p.id = s.program_id
   WHERE s.id = v_section;
  IF v_status IS DISTINCT FROM 'draft' THEN
    IF NOT (v_amend AND TG_OP = 'UPDATE' AND v_status = 'approved'
            AND (NEW.section_id, NEW.subject_id, NEW.meeting)
                IS NOT DISTINCT FROM (OLD.section_id, OLD.subject_id, OLD.meeting)) THEN
      RAISE EXCEPTION 'The schedule is already submitted; professor loading is locked';
    END IF;
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

CREATE OR REPLACE FUNCTION after_section_created() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO section_subjects (section_id, subject_id, meeting)
  SELECT NEW.id, sub.id, m.meeting
    FROM subjects sub
    CROSS JOIN (VALUES ('lecture'), ('laboratory')) m(meeting)
   WHERE sub.program_id = NEW.program_id AND sub.year_level = NEW.year_level
     AND subject_in_term(sub.semester, sub.offered_in_summer, NEW.semester)
     AND (m.meeting = 'lecture' OR sub.has_laboratory)
   ON CONFLICT (section_id, subject_id, meeting) DO NOTHING;
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
  INSERT INTO section_subjects (section_id, subject_id, meeting)
  SELECT sec.id, NEW.id, m.meeting
    FROM sections sec
    JOIN enrollment_term t ON t.school_year = sec.school_year AND t.semester = sec.semester
    CROSS JOIN (VALUES ('lecture'), ('laboratory')) m(meeting)
   WHERE sec.program_id = NEW.program_id AND sec.year_level = NEW.year_level AND sec.schedule_status = 'draft'
     AND subject_in_term(NEW.semester, NEW.offered_in_summer, sec.semester)
     AND (m.meeting = 'lecture' OR NEW.has_laboratory)
   ON CONFLICT (section_id, subject_id, meeting) DO NOTHING;
  RETURN NULL;
END;
$$;

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
   WHERE st.id = p_student AND a.withdrawn_at IS NULL;
  IF v_program IS NULL THEN
    RETURN NULL;
  END IF;

  FOR v_sec IN
    SELECT sec.id, sec.name, sec.year_level, sec.capacity, p.code
      FROM sections sec
      JOIN programs p ON p.id = sec.program_id
      JOIN enrollment_term t ON t.school_year = sec.school_year AND t.semester = sec.semester
     WHERE sec.program_id = v_program AND sec.year_level = 1
     ORDER BY sec.name, sec.id
       FOR UPDATE OF sec
  LOOP
    IF (SELECT count(*) FROM student_sections WHERE section_id = v_sec.id) < v_sec.capacity THEN
      INSERT INTO student_sections (student_id, section_id) VALUES (p_student, v_sec.id);
      INSERT INTO notifications (user_id, kind, title, message)
      VALUES (v_user, 'section_placed', 'Your section',
              'You are placed in ' || v_sec.code || ' ' || v_sec.year_level || v_sec.name
              || '. Your college is preparing your schedule.');
      RETURN v_sec.id;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

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
       AND a.withdrawn_at IS NULL
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
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = p_student AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;

  SELECT sec.id, sec.name, sec.year_level, sec.program_id, sec.school_year, sec.semester, p.code INTO v_sec
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
  IF NOT EXISTS (SELECT 1 FROM enrollment_term t
                  WHERE t.school_year = v_sec.school_year AND t.semester = v_sec.semester) THEN
    RAISE EXCEPTION 'Only a section of the current term can be used';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips
              WHERE student_id = p_student AND school_year = v_sec.school_year AND semester = v_sec.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the section can no longer be changed';
  END IF;

  SELECT section_id INTO v_old FROM student_sections
   WHERE student_id = p_student AND school_year = v_sec.school_year AND semester = v_sec.semester
     FOR UPDATE;
  IF v_old = p_section THEN
    RAISE EXCEPTION 'The student is already in this section';
  END IF;

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', v_reason, true);
  END IF;

  IF v_old IS NULL THEN
    INSERT INTO student_sections (student_id, section_id) VALUES (p_student, p_section);
  ELSE
    UPDATE student_sections SET section_id = p_section
     WHERE student_id = p_student AND school_year = v_sec.school_year AND semester = v_sec.semester;
  END IF;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user,
          CASE WHEN v_old IS NULL THEN 'section_placed' ELSE 'section_moved' END,
          CASE WHEN v_old IS NULL THEN 'Your section' ELSE 'Your section has changed' END,
          'You are placed in ' || v_sec.code || ' ' || v_sec.year_level || v_sec.name
          || '. Your college is preparing your schedule.');

  IF v_reason IS NOT NULL THEN
    PERFORM set_config('app.audit_reason', '', true);
  END IF;
  RETURN p_section;
END;
$$;

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

CREATE OR REPLACE FUNCTION notify_schedule_approved() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_code text;
BEGIN
  SELECT code INTO v_code FROM programs WHERE id = NEW.program_id;
  INSERT INTO notifications (user_id, kind, title, message)
  SELECT a.user_id, 'schedule_approved', 'Your schedule is approved',
         'The schedule for ' || v_code || ' ' || NEW.year_level || NEW.name
         || ' is approved. Your next step is the assessment slip from the Registrar.'
    FROM student_sections ss
    JOIN students st ON st.id = ss.student_id
    JOIN applicants a ON a.id = st.applicant_id
   WHERE ss.section_id = NEW.id;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION amend_schedule(
  p_section_subject uuid,
  p_professor uuid,
  p_room uuid,
  p_day smallint,
  p_start time,
  p_end time,
  p_reason text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_reason  text := nullif(trim(coalesce(p_reason, '')), '');
  v_section uuid;
  v_status  text;
  v_college uuid;
  v_label   text;
  v_subject text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary, the Dean or Admin can change an approved schedule';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A reason is required to change an approved schedule';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  SELECT ss.section_id, s.schedule_status, p.college_id,
         p.code || ' ' || s.year_level || s.name,
         sub.code || CASE WHEN ss.meeting = 'laboratory' THEN ' Lab' ELSE '' END
    INTO v_section, v_status, v_college, v_label, v_subject
    FROM section_subjects ss
    JOIN sections s ON s.id = ss.section_id
    JOIN programs p ON p.id = s.program_id
    JOIN subjects sub ON sub.id = ss.subject_id
   WHERE ss.id = p_section_subject
     FOR UPDATE OF ss;
  IF v_section IS NULL THEN
    RAISE EXCEPTION 'Subject not found';
  END IF;
  IF v_role <> 'admin' AND app_college_id() IS DISTINCT FROM v_college THEN
    RAISE EXCEPTION 'This section belongs to another college';
  END IF;
  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved schedule is changed this way; edit a draft schedule directly';
  END IF;
  IF EXISTS (SELECT 1 FROM cors c
               JOIN student_subjects ls ON ls.student_id = c.student_id
                                       AND ls.school_year = c.school_year AND ls.semester = c.semester
               JOIN section_subjects x ON x.id = ls.section_subject_id
              WHERE x.section_id = v_section) THEN
    RAISE EXCEPTION 'A COR was already issued to a student in this section, so its schedule can no longer be changed';
  END IF;

  PERFORM set_config('app.amend_schedule', 'on', true);
  PERFORM set_config('app.audit_reason', v_reason, true);
  UPDATE section_subjects
     SET professor_id = p_professor,
         room_id = p_room,
         day_of_week = p_day,
         start_time = p_start,
         end_time = p_end
   WHERE id = p_section_subject;
  PERFORM set_config('app.amend_schedule', '', true);
  PERFORM set_config('app.audit_reason', '', true);

  INSERT INTO notifications (user_id, kind, title, message)
  SELECT a.user_id, 'schedule_changed', 'Your schedule changed',
         v_subject || ' in ' || v_label || ' was changed. Your COR will show the final schedule.'
    FROM student_subjects ls
    JOIN students st ON st.id = ls.student_id
    JOIN applicants a ON a.id = st.applicant_id
   WHERE ls.section_subject_id = p_section_subject;
END;
$$;

CREATE OR REPLACE FUNCTION student_schedule_json(p_student uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'code', sub.code, 'title', sub.title,
           'meeting', ss.meeting,
           'units', CASE WHEN ss.meeting = 'laboratory' THEN 0 ELSE sub.units END,
           'section', pr.code || ' ' || sec.year_level || sec.name,
           'professor', pu.full_name, 'room', r.name,
           'day', ss.day_of_week,
           'start', to_char(ss.start_time, 'HH24:MI'),
           'end', to_char(ss.end_time, 'HH24:MI')
         ) ORDER BY sub.code, (ss.meeting = 'laboratory')), '[]'::jsonb)
    FROM student_enrollment(p_student) sts
    JOIN student_subjects ls ON ls.student_id = sts.student_id
                            AND ls.school_year = sts.school_year AND ls.semester = sts.semester
    JOIN section_subjects ss ON ss.id = ls.section_subject_id
    JOIN sections sec ON sec.id = ss.section_id
    JOIN programs pr ON pr.id = sec.program_id
    JOIN subjects sub ON sub.id = ss.subject_id
    LEFT JOIN users pu ON pu.id = ss.professor_id
    LEFT JOIN rooms r ON r.id = ss.room_id
$$;

CREATE OR REPLACE FUNCTION student_load_ready(p_student uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
           SELECT 1 FROM student_enrollment(p_student) e
             JOIN student_subjects ls ON ls.student_id = e.student_id
                                     AND ls.school_year = e.school_year AND ls.semester = e.semester)
     AND NOT EXISTS (
           SELECT 1 FROM student_enrollment(p_student) e
             JOIN student_subjects ls ON ls.student_id = e.student_id
                                     AND ls.school_year = e.school_year AND ls.semester = e.semester
             JOIN section_subjects x ON x.id = ls.section_subject_id
             JOIN sections s ON s.id = x.section_id
            WHERE s.schedule_status <> 'approved')
$$;

CREATE OR REPLACE FUNCTION in_section_subject(p_student uuid, p_section uuid, p_subject uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM student_subjects ls
      JOIN section_subjects x ON x.id = ls.section_subject_id
     WHERE ls.student_id = p_student AND x.section_id = p_section AND x.subject_id = p_subject)
$$;

CREATE OR REPLACE FUNCTION refuse_direct_load_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.load_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'A student''s subjects change only through the load builder';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION copy_section_load(p_student uuid, p_section uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM set_config('app.load_write', 'on', true);
  INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source)
  SELECT p_student, sec.school_year, sec.semester, x.id, 'section'
    FROM section_subjects x
    JOIN sections sec ON sec.id = x.section_id
   WHERE x.section_id = p_section
     AND NOT EXISTS (SELECT 1 FROM student_blocking_prerequisites(p_student, x.subject_id))
  ON CONFLICT DO NOTHING;
  PERFORM set_config('app.load_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION load_after_enrollment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN

    DELETE FROM student_subjects
     WHERE student_id = NEW.student_id AND school_year = NEW.school_year AND semester = NEW.semester
       AND source = 'section';
  END IF;
  PERFORM copy_section_load(NEW.student_id, NEW.section_id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION load_after_section_subject() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM set_config('app.load_write', 'on', true);
  INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source)
  SELECT ss.student_id, ss.school_year, ss.semester, NEW.id, 'section'
    FROM student_sections ss
   WHERE ss.section_id = NEW.section_id
     AND NOT EXISTS (SELECT 1 FROM student_blocking_prerequisites(ss.student_id, NEW.subject_id))
  ON CONFLICT DO NOTHING;
  PERFORM set_config('app.load_write', 'off', true);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_slip_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_program uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue an assessment slip';
  END IF;
  SELECT e.school_year, e.semester INTO NEW.school_year, NEW.semester FROM student_enrollment(NEW.student_id) e;
  IF NOT student_load_ready(NEW.student_id) THEN
    RAISE EXCEPTION 'The student''s schedule must be approved before the assessment slip';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = NEW.student_id;
  NEW.payment_required := coalesce(
    (SELECT payment_required FROM program_payment_settings WHERE program_id = v_program), false);
  NEW.schedule := student_schedule_json(NEW.student_id);
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION open_payment_after_slip() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.payment_required THEN
    INSERT INTO payments (student_id, school_year, semester)
    VALUES (NEW.student_id, NEW.school_year, NEW.semester);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION set_payment_term() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.school_year IS NULL OR NEW.semester IS NULL THEN
    SELECT e.school_year, e.semester INTO NEW.school_year, NEW.semester FROM student_enrollment(NEW.student_id) e;
    IF NEW.school_year IS NULL THEN
      SELECT t.school_year, t.semester INTO NEW.school_year, NEW.semester FROM enrollment_term t;
    END IF;
    IF NEW.school_year IS NULL THEN
      RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

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

  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student
     FOR UPDATE OF st;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;

  IF EXISTS (SELECT 1 FROM assessment_slips sl
               CROSS JOIN LATERAL student_enrollment(p_student) e
              WHERE sl.student_id = p_student AND sl.school_year = e.school_year AND sl.semester = e.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued';
  END IF;

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

CREATE OR REPLACE FUNCTION slip_ready_students()
RETURNS TABLE (
  student_id     uuid,
  student_number text,
  full_name      text,
  program_code   text,
  section        text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can see who is ready for an assessment slip';
  END IF;

  RETURN QUERY
  SELECT st.id,
         st.student_number::text,
         u.full_name::text,
         p.code::text,
         (p.code || ' ' || sec.year_level || sec.name)::text
    FROM students st
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    CROSS JOIN LATERAL student_enrollment(st.id) e
    JOIN sections sec ON sec.id = e.section_id
   WHERE student_load_ready(st.id)
     AND NOT EXISTS (SELECT 1 FROM assessment_slips sl
                      WHERE sl.student_id = st.id AND sl.school_year = e.school_year AND sl.semester = e.semester)
   ORDER BY st.student_number;
END;
$$;

CREATE OR REPLACE FUNCTION issue_all_ready_slips(OUT issued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue assessment slips';
  END IF;

  issued := 0;
  FOR r IN SELECT q.student_id FROM slip_ready_students() q
  LOOP
    PERFORM issue_assessment_slip(r.student_id);
    issued := issued + 1;
  END LOOP;
END;
$$;

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
           'section', p.code || ' ' || sec.year_level || sec.name,
           'issuedAt', sl.issued_at,
           'paymentRequired', sl.payment_required,
           'subjects', sl.schedule
         )
    INTO v_result
    FROM student_enrollment(p_student) sts
    JOIN assessment_slips sl ON sl.student_id = p_student
                            AND sl.school_year = sts.school_year AND sl.semester = sts.semester
    JOIN students st ON st.id = sl.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN sections sec ON sec.id = sts.section_id;

  RETURN v_result;
END;
$$;

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

CREATE OR REPLACE FUNCTION record_payment(
  p_student uuid, p_amount_due numeric, p_amount_paid numeric, p_receipt_no text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_payment payments%ROWTYPE;
  v_user    uuid;
  v_due     numeric;
  v_paid    numeric;
  v_receipt text := nullif(btrim(coalesce(p_receipt_no, '')), '');
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance or Admin can record a payment';
  END IF;

  IF p_amount_due IS NULL OR p_amount_due < 0 OR p_amount_due > 9999999999.99 THEN
    RAISE EXCEPTION 'Enter the amount due';
  END IF;
  IF p_amount_paid IS NULL OR p_amount_paid < 0 OR p_amount_paid > 9999999999.99 THEN
    RAISE EXCEPTION 'Enter the amount paid';
  END IF;
  v_due  := round(p_amount_due, 2);
  v_paid := round(p_amount_paid, 2);
  IF v_paid < v_due THEN
    RAISE EXCEPTION 'The amount paid must cover the amount due';
  END IF;
  IF v_paid > 0 AND v_receipt IS NULL THEN
    RAISE EXCEPTION 'Enter the receipt number';
  END IF;
  IF v_receipt IS NOT NULL AND length(v_receipt) > 60 THEN
    RAISE EXCEPTION 'The receipt number is longer than 60 characters';
  END IF;

  SELECT pay.* INTO v_payment
    FROM student_enrollment(p_student) e
    JOIN payments pay ON pay.student_id = p_student
                     AND pay.school_year = e.school_year AND pay.semester = e.semester
     FOR UPDATE OF pay;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This student has no payment to record';
  END IF;
  IF v_payment.status = 'cleared' THEN
    RAISE EXCEPTION 'This payment was already recorded';
  END IF;

  UPDATE payments
     SET amount_due = v_due, amount_paid = v_paid, receipt_no = v_receipt, status = 'cleared'
   WHERE id = v_payment.id;

  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (
    v_user, 'payment_cleared', 'Your payment is cleared',
    'Finance recorded your payment. Next, the Registrar issues your COR.'
  );

  RETURN v_payment.id;
END;
$$;

CREATE OR REPLACE FUNCTION payment_queue(p_status text)
RETURNS TABLE (
  student_id     uuid,
  student_number text,
  full_name      text,
  program_code   text,
  section        text,
  amount_due     numeric,
  amount_paid    numeric,
  receipt_no     text,
  cleared_at     timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance or Admin can see payments';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('pending','cleared') THEN
    RAISE EXCEPTION 'Unknown payment status';
  END IF;

  RETURN QUERY
  SELECT st.id,
         st.student_number::text,
         u.full_name::text,
         p.code::text,
         (p.code || ' ' || sec.year_level || sec.name)::text,
         pay.amount_due::numeric,
         pay.amount_paid::numeric,
         pay.receipt_no::text,
         pay.cleared_at
    FROM payments pay
    JOIN students st ON st.id = pay.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    LEFT JOIN student_sections ss ON ss.student_id = st.id
                                 AND ss.school_year = pay.school_year AND ss.semester = pay.semester
    LEFT JOIN sections sec ON sec.id = ss.section_id
   WHERE pay.status = p_status
   ORDER BY (CASE WHEN pay.status = 'cleared' THEN pay.cleared_at END) DESC NULLS LAST,
            st.student_number;
END;
$$;

CREATE OR REPLACE FUNCTION my_payment_status() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT pay.status
    FROM student_enrollment(my_student_id()) e
    JOIN payments pay ON pay.student_id = my_student_id()
                     AND pay.school_year = e.school_year AND pay.semester = e.semester
$$;

CREATE OR REPLACE FUNCTION enforce_cor_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slip assessment_slips%ROWTYPE;
  v_term enrollment_term%ROWTYPE;
  v_e    student_sections%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can issue a COR';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = NEW.student_id AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;
  SELECT * INTO v_e FROM student_enrollment(NEW.student_id);
  SELECT * INTO v_slip FROM assessment_slips
   WHERE student_id = NEW.student_id AND school_year = v_e.school_year AND semester = v_e.semester;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The assessment slip must be issued before the COR';
  END IF;
  IF v_slip.payment_required AND NOT EXISTS (
       SELECT 1 FROM payments
        WHERE student_id = NEW.student_id AND school_year = v_e.school_year AND semester = v_e.semester
          AND status = 'cleared') THEN
    RAISE EXCEPTION 'Payment must be cleared before the COR';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them before issuing a COR';
  END IF;
  NEW.school_year := v_e.school_year;
  NEW.semester := v_e.semester;
  NEW.schedule := student_schedule_json(NEW.student_id);
  NEW.issued_by := current_actor_id();
  NEW.issued_at := now();
  RETURN NEW;
END;
$$;

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

  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student
     FOR UPDATE OF st;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;

  IF EXISTS (SELECT 1 FROM cors c
               CROSS JOIN LATERAL student_enrollment(p_student) e
              WHERE c.student_id = p_student AND c.school_year = e.school_year AND c.semester = e.semester) THEN
    RAISE EXCEPTION 'The COR was already issued';
  END IF;

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

CREATE OR REPLACE FUNCTION cor_ready_students()
RETURNS TABLE (
  student_id     uuid,
  student_number text,
  full_name      text,
  program_code   text,
  section        text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can see who is ready for a COR';
  END IF;

  RETURN QUERY
  SELECT st.id,
         st.student_number::text,
         u.full_name::text,
         p.code::text,
         (p.code || ' ' || sec.year_level || sec.name)::text
    FROM students st
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    CROSS JOIN LATERAL student_enrollment(st.id) e
    JOIN sections sec ON sec.id = e.section_id
    JOIN assessment_slips sl ON sl.student_id = st.id AND sl.school_year = e.school_year AND sl.semester = e.semester
   WHERE a.withdrawn_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM cors c
                      WHERE c.student_id = st.id AND c.school_year = e.school_year AND c.semester = e.semester)
     AND (NOT sl.payment_required
          OR EXISTS (SELECT 1 FROM payments pay
                      WHERE pay.student_id = st.id AND pay.school_year = e.school_year
                        AND pay.semester = e.semester AND pay.status = 'cleared'))
   ORDER BY st.student_number;
END;
$$;

CREATE OR REPLACE FUNCTION issue_all_ready_cors(OUT issued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can issue a COR';
  END IF;

  issued := 0;
  FOR r IN SELECT q.student_id FROM cor_ready_students() q
  LOOP
    PERFORM issue_cor(r.student_id);
    issued := issued + 1;
  END LOOP;
END;
$$;

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
           'section', p.code || ' ' || sec.year_level || sec.name,
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
           'subjects', c.schedule
         )
    INTO v_result
    FROM student_enrollment(p_student) sts
    JOIN cors c ON c.student_id = p_student AND c.school_year = sts.school_year AND c.semester = sts.semester
    JOIN students st ON st.id = c.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    JOIN colleges col ON col.id = p.college_id
    JOIN assessment_slips sl ON sl.student_id = st.id AND sl.school_year = c.school_year AND sl.semester = c.semester
    JOIN sections sec ON sec.id = sts.section_id
    JOIN users iu ON iu.id = c.issued_by
    LEFT JOIN payments pay ON pay.student_id = st.id AND pay.status = 'cleared'
                          AND pay.school_year = c.school_year AND pay.semester = c.semester;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION my_schedule_changed() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((
    SELECT sl.schedule IS DISTINCT FROM student_schedule_json(sl.student_id)
           AND NOT EXISTS (SELECT 1 FROM cors c
                            WHERE c.student_id = sl.student_id
                              AND c.school_year = sl.school_year AND c.semester = sl.semester)
      FROM student_enrollment(my_student_id()) e
      JOIN assessment_slips sl ON sl.student_id = my_student_id()
                              AND sl.school_year = e.school_year AND sl.semester = e.semester
  ), false)
$$;

CREATE OR REPLACE FUNCTION enforce_withdrawal_columns() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.withdrawing', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NOT NULL OR NEW.withdrawn_reason IS NOT NULL THEN
      RAISE EXCEPTION 'Use the withdraw action to withdraw an applicant';
    END IF;
  ELSIF (NEW.withdrawn_at, NEW.withdrawn_by, NEW.withdrawn_reason)
        IS DISTINCT FROM (OLD.withdrawn_at, OLD.withdrawn_by, OLD.withdrawn_reason) THEN
    RAISE EXCEPTION 'Use the withdraw action to change a withdrawal';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION withdraw_enrollment_core(p_applicant uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_app     applicants%ROWTYPE;
  v_student uuid;
  v_year    text;
  v_sem     text;
  v_seats   integer := 0;
  v_message text;
BEGIN
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;

  SELECT * INTO v_app FROM applicants WHERE id = p_applicant FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
  END IF;
  IF v_app.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'This enrollment was already withdrawn';
  END IF;

  SELECT id INTO v_student FROM students WHERE applicant_id = v_app.id;

  PERFORM set_config('app.audit_reason', v_reason, true);

  PERFORM set_config('app.withdrawing', 'on', true);
  UPDATE applicants
     SET withdrawn_at = now(), withdrawn_by = current_actor_id(), withdrawn_reason = v_reason
   WHERE id = v_app.id;
  PERFORM set_config('app.withdrawing', '', true);

  DELETE FROM reschedule_requests
   WHERE booking_id IN (SELECT id FROM visit_bookings WHERE applicant_id = v_app.id AND status = 'booked');
  DELETE FROM visit_bookings WHERE applicant_id = v_app.id AND status = 'booked';

  IF v_student IS NOT NULL THEN

    SELECT e.school_year, e.semester INTO v_year, v_sem FROM student_enrollment(v_student) e;

    DELETE FROM payments
     WHERE student_id = v_student AND status = 'pending'
       AND (v_year IS NULL OR (school_year = v_year AND semester = v_sem));

    IF v_year IS NOT NULL THEN
      DELETE FROM student_sections
       WHERE student_id = v_student AND school_year = v_year AND semester = v_sem;
      GET DIAGNOSTICS v_seats = ROW_COUNT;
      IF v_seats > 0 THEN

        PERFORM place_waiting_students(v_app.program_id);
      END IF;
    END IF;
  END IF;

  IF v_app.user_id = current_actor_id() THEN
    v_message := 'You withdrew your enrollment. Your visit date and your seat were released. To come back, contact the Registrar.';
  ELSE
    v_message := 'The Registrar withdrew your enrollment. Reason: ' || v_reason;
  END IF;
  INSERT INTO notifications (user_id, kind, title, message, email_status)
  VALUES (v_app.user_id, 'withdrawn', 'Enrollment withdrawn', v_message, 'pending');

  PERFORM set_config('app.audit_reason', '', true);
  RETURN v_app.id;
END;
$$;

CREATE OR REPLACE FUNCTION withdraw_my_enrollment(p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_applicant uuid;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('applicant','student') THEN
    RAISE EXCEPTION 'Only an applicant or student can withdraw their own enrollment';
  END IF;

  v_applicant := my_applicant_id();
  IF v_applicant IS NULL THEN
    RAISE EXCEPTION 'No enrollment found';
  END IF;

  IF EXISTS (SELECT 1
               FROM students st
               CROSS JOIN LATERAL student_enrollment(st.id) e
               JOIN cors c ON c.student_id = st.id AND c.school_year = e.school_year AND c.semester = e.semester
              WHERE st.applicant_id = v_applicant) THEN
    RAISE EXCEPTION 'You are already enrolled. Ask the Registrar to withdraw you';
  END IF;

  RETURN withdraw_enrollment_core(v_applicant, p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION withdraw_applicant(p_applicant uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can withdraw an applicant';
  END IF;
  RETURN withdraw_enrollment_core(p_applicant, p_reason);
END;
$$;

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
    v_changed := array_append(v_changed, 'name');
  END IF;
  IF lower(v_user.email::text) IS DISTINCT FROM v_email THEN
    IF EXISTS (SELECT 1 FROM users WHERE email = v_email AND id <> v_user.id) THEN
      RAISE EXCEPTION 'This email already belongs to another account';
    END IF;
    v_changed := array_append(v_changed, 'email');
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

CREATE OR REPLACE FUNCTION record_admissions_status(
  p_student uuid, p_stage text, p_ok boolean, p_error text DEFAULT NULL, p_permanent boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_stage IS NULL OR p_stage NOT IN ('student','enrolled') THEN
    RAISE EXCEPTION 'Unknown stage';
  END IF;

  IF p_ok THEN
    INSERT INTO admissions_status_queue (student_id, stage_sent, attempts, last_attempt_at, last_error)
    VALUES (p_student, p_stage, 0, now(), NULL)
    ON CONFLICT (student_id) DO UPDATE SET
      stage_sent      = CASE WHEN admissions_status_queue.stage_sent = 'enrolled' THEN 'enrolled' ELSE EXCLUDED.stage_sent END,
      attempts        = 0,
      last_attempt_at = now(),
      last_error      = NULL,
      updated_at      = now();
  ELSE

    INSERT INTO admissions_status_queue (student_id, stage_sent, attempts, last_attempt_at, last_error)
    VALUES (p_student, NULL, CASE WHEN p_permanent THEN 20 ELSE 1 END, now(), left(p_error, 500))
    ON CONFLICT (student_id) DO UPDATE SET
      attempts        = least(admissions_status_queue.attempts + CASE WHEN p_permanent THEN 20 ELSE 1 END, 20),
      last_attempt_at = now(),
      last_error      = left(p_error, 500),
      updated_at      = now();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION admissions_status_due(p_limit integer DEFAULT 5)
RETURNS TABLE (student_id uuid, applicant_ref varchar, student_number varchar, stage text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, a.applicant_ref, s.student_number,
         CASE WHEN EXISTS (SELECT 1 FROM cors c WHERE c.student_id = s.id) THEN 'enrolled' ELSE 'student' END
    FROM students s
    JOIN applicants a ON a.id = s.applicant_id
    LEFT JOIN admissions_status_queue q ON q.student_id = s.id
   WHERE q.stage_sent IS DISTINCT FROM
           (CASE WHEN EXISTS (SELECT 1 FROM cors c WHERE c.student_id = s.id) THEN 'enrolled' ELSE 'student' END)
     AND coalesce(q.attempts, 0) < 20
     AND (q.last_attempt_at IS NULL
          OR q.last_attempt_at <= now() - least(q.attempts, 12) * interval '5 minutes')
   ORDER BY coalesce(q.last_attempt_at, s.created_at), s.id
   LIMIT greatest(p_limit, 0)
$$;

CREATE OR REPLACE FUNCTION refuse_direct_grade_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.grade_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Grades change only through the grading functions';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION grading_scale_ready() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM grade_bands b WHERE NOT b.is_descriptive)
$$;

CREATE OR REPLACE FUNCTION resolve_grade(p_text text) RETURNS TABLE (r_text text, r_outcome text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t text := btrim(coalesce(p_text, ''));
  v_n numeric;
BEGIN
  IF v_t = '' THEN
    RETURN;
  END IF;
  IF v_t ~ '^[0-9]{1,4}(\.[0-9]{1,2})?$' THEN
    v_n := v_t::numeric;
    RETURN QUERY
      SELECT v_t, b.outcome FROM grade_bands b
       WHERE NOT b.is_descriptive AND b.from_value IS NOT NULL AND v_n BETWEEN b.from_value AND b.to_value
       ORDER BY b.sort_order LIMIT 1;
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;
  RETURN QUERY
    SELECT b.label::text, b.outcome FROM grade_bands b
     WHERE NOT b.is_descriptive AND lower(b.label) = lower(v_t)
     ORDER BY b.sort_order LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION grading_scale() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('admin','professor','dean','registrar') THEN
    RAISE EXCEPTION 'You cannot read the grading scale';
  END IF;
  RETURN jsonb_build_object(
    'incWindowDays', (SELECT inc_window_days FROM grading_settings),
    'bands', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'label', b.label, 'outcome', b.outcome, 'descriptive', b.is_descriptive,
               'from', b.from_value, 'to', b.to_value) ORDER BY b.sort_order, b.label)
        FROM grade_bands b), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION save_grade_scale(p_bands jsonb, p_inc_days integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  e jsonb;
  i integer := 0;
  v_label text;
  v_outcome text;
  v_desc boolean;
  v_from numeric;
  v_to numeric;
  v_a text;
  v_b text;
BEGIN
  IF app_role() IS NULL OR app_role() <> 'admin' THEN
    RAISE EXCEPTION 'Only Admin can set the grading scale';
  END IF;
  IF jsonb_typeof(p_bands) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'The bands are missing';
  END IF;
  IF p_inc_days IS NULL OR p_inc_days < 1 OR p_inc_days > 365 THEN
    RAISE EXCEPTION 'The incomplete window must be from 1 to 365 days';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  DELETE FROM grade_bands WHERE true;

  FOR e IN SELECT value FROM jsonb_array_elements(p_bands) LOOP
    i := i + 1;
    v_label := btrim(coalesce(e->>'label', ''));
    v_outcome := coalesce(e->>'outcome', '');
    v_desc := coalesce((e->>'descriptive')::boolean, false);
    v_from := nullif(e->>'from', '')::numeric;
    v_to := nullif(e->>'to', '')::numeric;
    IF v_label = '' OR length(v_label) > 30 THEN
      RAISE EXCEPTION 'Band % needs a label of 1 to 30 characters', i;
    END IF;
    IF v_outcome NOT IN ('passed','incomplete','failed','dropped') THEN
      RAISE EXCEPTION 'Band % needs an outcome', v_label;
    END IF;
    IF (v_from IS NULL) <> (v_to IS NULL) OR (v_from IS NOT NULL AND v_from > v_to) THEN
      RAISE EXCEPTION 'The range of band % is not valid', v_label;
    END IF;
    IF v_desc THEN
      v_outcome := 'passed';
    END IF;
    IF EXISTS (SELECT 1 FROM grade_bands WHERE lower(label) = lower(v_label)) THEN
      RAISE EXCEPTION 'Two bands are named %', v_label;
    END IF;
    INSERT INTO grade_bands (label, outcome, is_descriptive, from_value, to_value, sort_order)
    VALUES (v_label, v_outcome, v_desc, v_from, v_to, i);
  END LOOP;

  SELECT a.label, b.label INTO v_a, v_b
    FROM grade_bands a
    JOIN grade_bands b ON a.id < b.id
   WHERE NOT a.is_descriptive AND NOT b.is_descriptive
     AND a.from_value IS NOT NULL AND b.from_value IS NOT NULL
     AND a.from_value <= b.to_value AND b.from_value <= a.to_value
   LIMIT 1;
  IF v_a IS NOT NULL THEN
    RAISE EXCEPTION 'The bands % and % overlap', v_a, v_b;
  END IF;

  UPDATE grading_settings SET inc_window_days = p_inc_days, updated_at = now();
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION can_see_sheet(p_section uuid, p_subject uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE app_role()
    WHEN 'admin' THEN true
    WHEN 'registrar' THEN true
    WHEN 'dean' THEN section_in_my_college(p_section)
    WHEN 'professor' THEN EXISTS (
      SELECT 1 FROM section_subjects x
       WHERE x.section_id = p_section AND x.subject_id = p_subject AND x.professor_id = current_actor_id())
    ELSE false
  END
$$;

CREATE OR REPLACE FUNCTION grade_sections() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_college uuid := app_college_id();
  v_result jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','dean','registrar','admin') THEN
    RAISE EXCEPTION 'You cannot read grades';
  END IF;

  SELECT coalesce(jsonb_agg(q.x ORDER BY q.x->>'label', q.x->>'code'), '[]'::jsonb) INTO v_result
    FROM (
      SELECT jsonb_build_object(
               'sectionId', sec.id,
               'subjectId', sub.id,
               'label', p.code || ' ' || sec.year_level || sec.name,
               'code', sub.code,
               'title', sub.title,
               'schoolYear', sec.school_year,
               'semester', sec.semester,
               'status', coalesce(gs.status, 'not_submitted'),
               'students', (SELECT count(DISTINCT ls.student_id) FROM student_subjects ls
                              JOIN section_subjects y ON y.id = ls.section_subject_id
                             WHERE y.section_id = sec.id AND y.subject_id = sub.id),
               'graded', (SELECT count(*) FROM grades g WHERE g.sheet_id = gs.id),
               'professor', (SELECT u.full_name FROM section_subjects x JOIN users u ON u.id = x.professor_id
                              WHERE x.section_id = sec.id AND x.subject_id = sub.id AND x.professor_id IS NOT NULL
                              ORDER BY x.meeting LIMIT 1)
             ) AS x
        FROM enrollment_term t
        JOIN sections sec ON sec.school_year = t.school_year AND sec.semester = t.semester
        JOIN programs p ON p.id = sec.program_id
        JOIN (SELECT DISTINCT section_id, subject_id FROM section_subjects) ssub ON ssub.section_id = sec.id
        JOIN subjects sub ON sub.id = ssub.subject_id
        LEFT JOIN grade_sheets gs ON gs.section_id = sec.id AND gs.subject_id = sub.id
       WHERE v_role IN ('registrar','admin')
          OR (v_role = 'dean' AND p.college_id = v_college)
          OR (v_role = 'professor' AND EXISTS (
                SELECT 1 FROM section_subjects x
                 WHERE x.section_id = sec.id AND x.subject_id = sub.id AND x.professor_id = v_actor))
    ) q;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION grade_sheet(p_section uuid, p_subject uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sheet grade_sheets%ROWTYPE;
  v_head record;
BEGIN
  IF NOT can_see_sheet(p_section, p_subject) THEN
    RAISE EXCEPTION 'You cannot read these grades';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject;
  SELECT p.code || ' ' || sec.year_level || sec.name AS label, sub.code, sub.title, sec.school_year, sec.semester
    INTO v_head
    FROM sections sec JOIN programs p ON p.id = sec.program_id, subjects sub
   WHERE sec.id = p_section AND sub.id = p_subject;
  IF v_head.label IS NULL THEN
    RAISE EXCEPTION 'That section subject was not found';
  END IF;

  RETURN jsonb_build_object(
    'sectionId', p_section,
    'subjectId', p_subject,
    'label', v_head.label,
    'code', v_head.code,
    'title', v_head.title,
    'schoolYear', v_head.school_year,
    'semester', v_head.semester,
    'status', coalesce(v_sheet.status, 'not_submitted'),
    'returnedReason', v_sheet.returned_reason,
    'students', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'studentId', st.id,
               'studentNumber', st.student_number,
               'fullName', u.full_name,
               'gradeId', g.id,
               'gradeText', g.grade_text,
               'outcome', g.outcome,
               'lapsed', coalesce(g.lapsed, false),
               'changePending', EXISTS (SELECT 1 FROM grade_changes c WHERE c.grade_id = g.id AND c.status IN ('pending_dean','pending_registrar'))
             ) ORDER BY st.student_number)
        FROM students st
        JOIN applicants a ON a.id = st.applicant_id
        JOIN users u ON u.id = a.user_id
        LEFT JOIN grades g ON g.sheet_id = v_sheet.id AND g.student_id = st.id
       WHERE in_section_subject(st.id, p_section, p_subject)), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION save_grades(p_section uuid, p_subject uuid, p_grades jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_sec sections%ROWTYPE;
  v_sheet grade_sheets%ROWTYPE;
  e jsonb;
  v_student uuid;
  v_text text;
  v_res record;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','admin') THEN
    RAISE EXCEPTION 'Only the Professor of this subject can enter grades';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM section_subjects x
        WHERE x.section_id = p_section AND x.subject_id = p_subject
          AND (v_role = 'admin' OR x.professor_id = v_actor)) THEN
    RAISE EXCEPTION 'Only the Professor of this subject can enter grades';
  END IF;
  IF NOT grading_scale_ready() THEN
    RAISE EXCEPTION 'The grading scale is not set. Ask Admin to set it in Content, Grading';
  END IF;
  IF jsonb_typeof(p_grades) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'The grades are missing';
  END IF;

  SELECT * INTO v_sec FROM sections WHERE id = p_section;
  PERFORM set_config('app.grade_write', 'on', true);
  INSERT INTO grade_sheets (section_id, subject_id, school_year, semester)
  VALUES (p_section, p_subject, v_sec.school_year, v_sec.semester)
  ON CONFLICT (section_id, subject_id) DO NOTHING;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;

  IF v_sheet.status = 'submitted' THEN
    RAISE EXCEPTION 'These grades are submitted. Ask the Dean to return them before editing';
  ELSIF v_sheet.status = 'approved' THEN
    RAISE EXCEPTION 'These grades are approved. Propose a grade change instead';
  END IF;

  FOR e IN SELECT value FROM jsonb_array_elements(p_grades) LOOP
    IF coalesce(e->>'studentId', '') !~ '^[0-9a-fA-F-]{36}$' THEN
      RAISE EXCEPTION 'A student is missing from the grades';
    END IF;
    v_student := (e->>'studentId')::uuid;
    IF NOT in_section_subject(v_student, p_section, p_subject) THEN
      RAISE EXCEPTION 'That student is not in this section';
    END IF;
    v_text := btrim(coalesce(e->>'grade', ''));
    IF v_text = '' THEN
      DELETE FROM grades WHERE sheet_id = v_sheet.id AND student_id = v_student;
      CONTINUE;
    END IF;
    SELECT * INTO v_res FROM resolve_grade(v_text);
    IF v_res.r_outcome IS NULL THEN
      RAISE EXCEPTION 'The grade "%" for student % is not on the grading scale',
        v_text, (SELECT student_number FROM students WHERE id = v_student);
    END IF;
    INSERT INTO grades (sheet_id, section_id, subject_id, student_id, school_year, semester, grade_text, outcome, entered_by)
    VALUES (v_sheet.id, p_section, p_subject, v_student, v_sheet.school_year, v_sheet.semester, v_res.r_text, v_res.r_outcome, v_actor)
    ON CONFLICT (sheet_id, student_id) DO UPDATE
       SET grade_text = EXCLUDED.grade_text, outcome = EXCLUDED.outcome,
           entered_by = EXCLUDED.entered_by, updated_at = now();
  END LOOP;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION submit_grades(p_section uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_sheet grade_sheets%ROWTYPE;
  v_missing text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','admin') THEN
    RAISE EXCEPTION 'Only the Professor of this subject can submit grades';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM section_subjects x
        WHERE x.section_id = p_section AND x.subject_id = p_subject
          AND (v_role = 'admin' OR x.professor_id = v_actor)) THEN
    RAISE EXCEPTION 'Only the Professor of this subject can submit grades';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;
  IF v_sheet.id IS NULL OR v_sheet.status <> 'draft' THEN
    RAISE EXCEPTION 'There are no draft grades to submit';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM student_subjects ls
                   JOIN section_subjects x ON x.id = ls.section_subject_id
                  WHERE x.section_id = p_section AND x.subject_id = p_subject) THEN
    RAISE EXCEPTION 'This section has no students';
  END IF;
  SELECT st.student_number INTO v_missing
    FROM students st
   WHERE in_section_subject(st.id, p_section, p_subject)
     AND NOT EXISTS (SELECT 1 FROM grades g WHERE g.sheet_id = v_sheet.id AND g.student_id = st.id)
   ORDER BY st.student_number LIMIT 1;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Enter a grade for student % before submitting', v_missing;
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_sheets
     SET status = 'submitted', submitted_by = v_actor, submitted_at = now(), returned_reason = NULL
   WHERE id = v_sheet.id;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION approve_grades(p_section uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_sheet grade_sheets%ROWTYPE;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean of this college can approve grades';
  END IF;
  IF v_role = 'dean' AND NOT section_in_my_college(p_section) THEN
    RAISE EXCEPTION 'Only the Dean of this college can approve grades';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;
  IF v_sheet.id IS NULL OR v_sheet.status <> 'submitted' THEN
    RAISE EXCEPTION 'These grades are not waiting for approval';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_sheets SET status = 'approved', approved_by = current_actor_id(), approved_at = now() WHERE id = v_sheet.id;
  UPDATE grades SET outcome_since = now() WHERE sheet_id = v_sheet.id;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION return_grades(p_section uuid, p_subject uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_sheet grade_sheets%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_label text;
  v_code text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean of this college can return grades';
  END IF;
  IF v_role = 'dean' AND NOT section_in_my_college(p_section) THEN
    RAISE EXCEPTION 'Only the Dean of this college can return grades';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE section_id = p_section AND subject_id = p_subject FOR UPDATE;
  IF v_sheet.id IS NULL OR v_sheet.status <> 'submitted' THEN
    RAISE EXCEPTION 'These grades are not waiting for approval';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_sheets
     SET status = 'draft', submitted_by = NULL, submitted_at = NULL, returned_reason = v_reason
   WHERE id = v_sheet.id;
  PERFORM set_config('app.grade_write', 'off', true);

  SELECT p.code || ' ' || sec.year_level || sec.name, sub.code INTO v_label, v_code
    FROM sections sec JOIN programs p ON p.id = sec.program_id, subjects sub
   WHERE sec.id = p_section AND sub.id = p_subject;
  INSERT INTO notifications (user_id, kind, title, message)
  SELECT DISTINCT x.professor_id, 'grades_returned', 'Grades returned',
         'The Dean returned the grades for ' || v_code || ' in ' || v_label || '. Reason: ' || v_reason
    FROM section_subjects x
   WHERE x.section_id = p_section AND x.subject_id = p_subject AND x.professor_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION lapse_incomplete_grades() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count integer;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','dean','admin') THEN
    RAISE EXCEPTION 'You cannot run this';
  END IF;
  PERFORM set_config('app.grade_write', 'on', true);
  WITH gone AS (
    UPDATE grades g
       SET grade_text = '5.0', outcome = 'failed', lapsed = true, outcome_since = now(), updated_at = now()
      FROM grade_sheets gs, grading_settings s
     WHERE gs.id = g.sheet_id AND gs.status = 'approved'
       AND g.outcome = 'incomplete'
       AND g.outcome_since + make_interval(days => s.inc_window_days) < now()
       AND NOT EXISTS (SELECT 1 FROM grade_changes c WHERE c.grade_id = g.id AND c.status IN ('pending_dean','pending_registrar'))
    RETURNING g.id)
  SELECT count(*) INTO v_count FROM gone;
  PERFORM set_config('app.grade_write', 'off', true);
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION propose_grade_change(p_grade uuid, p_new_grade text, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_grade grades%ROWTYPE;
  v_sheet grade_sheets%ROWTYPE;
  v_res record;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_kind text;
  v_id uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','admin') THEN
    RAISE EXCEPTION 'Only the Professor of this subject can propose a grade change';
  END IF;
  SELECT * INTO v_grade FROM grades WHERE id = p_grade;
  IF v_grade.id IS NULL THEN
    RAISE EXCEPTION 'That grade was not found';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM section_subjects x
        WHERE x.section_id = v_grade.section_id AND x.subject_id = v_grade.subject_id
          AND (v_role = 'admin' OR x.professor_id = v_actor)) THEN
    RAISE EXCEPTION 'Only the Professor of this subject can propose a grade change';
  END IF;
  SELECT * INTO v_sheet FROM grade_sheets WHERE id = v_grade.sheet_id;
  IF v_sheet.status <> 'approved' THEN
    RAISE EXCEPTION 'The grades are not approved yet, so edit them directly';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_res FROM resolve_grade(p_new_grade);
  IF v_res.r_outcome IS NULL THEN
    RAISE EXCEPTION 'The grade "%" is not on the grading scale', btrim(coalesce(p_new_grade, ''));
  END IF;
  IF v_res.r_text = v_grade.grade_text THEN
    RAISE EXCEPTION 'The new grade is the same as the present grade';
  END IF;
  IF EXISTS (SELECT 1 FROM grade_changes c WHERE c.grade_id = p_grade AND c.status IN ('pending_dean','pending_registrar')) THEN
    RAISE EXCEPTION 'A change for this grade is already waiting';
  END IF;

  v_kind := CASE
    WHEN v_res.r_outcome = 'dropped' THEN 'drop'
    WHEN v_grade.outcome = 'incomplete' THEN 'inc_completion'
    ELSE 'correction' END;

  PERFORM set_config('app.grade_write', 'on', true);
  INSERT INTO grade_changes (grade_id, old_grade_text, old_outcome, new_grade_text, new_outcome, kind, reason, proposed_by)
  VALUES (p_grade, v_grade.grade_text, v_grade.outcome, v_res.r_text, v_res.r_outcome, v_kind, v_reason, v_actor)
  RETURNING id INTO v_id;
  PERFORM set_config('app.grade_write', 'off', true);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION sign_grade_change(p_change uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_change grade_changes%ROWTYPE;
  v_section uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean of this college can sign a grade change';
  END IF;
  SELECT * INTO v_change FROM grade_changes WHERE id = p_change FOR UPDATE;
  IF v_change.id IS NULL OR v_change.status <> 'pending_dean' THEN
    RAISE EXCEPTION 'This change is not waiting for the Dean';
  END IF;
  SELECT g.section_id INTO v_section FROM grades g WHERE g.id = v_change.grade_id;
  IF v_role = 'dean' AND NOT section_in_my_college(v_section) THEN
    RAISE EXCEPTION 'Only the Dean of this college can sign a grade change';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_changes SET status = 'pending_registrar', dean_by = current_actor_id(), dean_at = now() WHERE id = p_change;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION approve_grade_change(p_change uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_change grade_changes%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can approve a grade change';
  END IF;
  SELECT * INTO v_change FROM grade_changes WHERE id = p_change FOR UPDATE;
  IF v_change.id IS NULL OR v_change.status <> 'pending_registrar' THEN
    RAISE EXCEPTION 'This change is not waiting for the Registrar';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grades
     SET grade_text = v_change.new_grade_text, outcome = v_change.new_outcome, lapsed = false,
         outcome_since = now(), updated_at = now()
   WHERE id = v_change.grade_id;
  UPDATE grade_changes SET status = 'applied', registrar_by = current_actor_id(), registrar_at = now() WHERE id = p_change;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION reject_grade_change(p_change uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_change grade_changes%ROWTYPE;
  v_section uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','registrar','admin') THEN
    RAISE EXCEPTION 'Only the Dean or the Registrar can reject a grade change';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_change FROM grade_changes WHERE id = p_change FOR UPDATE;
  IF v_change.id IS NULL OR v_change.status NOT IN ('pending_dean','pending_registrar') THEN
    RAISE EXCEPTION 'This change is not waiting for a decision';
  END IF;
  IF v_role = 'dean' THEN
    SELECT g.section_id INTO v_section FROM grades g WHERE g.id = v_change.grade_id;
    IF v_change.status <> 'pending_dean' OR NOT section_in_my_college(v_section) THEN
      RAISE EXCEPTION 'Only the Dean of this college can reject this change';
    END IF;
  ELSIF v_role = 'registrar' AND v_change.status <> 'pending_registrar' THEN
    RAISE EXCEPTION 'This change is waiting for the Dean first';
  END IF;

  PERFORM set_config('app.grade_write', 'on', true);
  UPDATE grade_changes
     SET status = 'rejected', rejected_by = current_actor_id(), rejected_at = now(), rejected_reason = v_reason
   WHERE id = p_change;
  PERFORM set_config('app.grade_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION grade_changes_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_actor uuid := current_actor_id();
  v_college uuid := app_college_id();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('professor','dean','registrar','admin') THEN
    RAISE EXCEPTION 'You cannot read grade changes';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'id', c.id,
             'status', c.status,
             'kind', c.kind,
             'label', p.code || ' ' || sec.year_level || sec.name,
             'code', sub.code,
             'title', sub.title,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'oldGrade', c.old_grade_text,
             'oldOutcome', c.old_outcome,
             'newGrade', c.new_grade_text,
             'newOutcome', c.new_outcome,
             'reason', c.reason,
             'proposedBy', (SELECT pu.full_name FROM users pu WHERE pu.id = c.proposed_by),
             'proposedAt', c.proposed_at
           ) ORDER BY c.proposed_at)
      FROM grade_changes c
      JOIN grades g ON g.id = c.grade_id
      JOIN sections sec ON sec.id = g.section_id
      JOIN programs p ON p.id = sec.program_id
      JOIN subjects sub ON sub.id = g.subject_id
      JOIN students st ON st.id = g.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
     WHERE c.status IN ('pending_dean','pending_registrar')
       AND (v_role = 'admin'
            OR (v_role = 'dean' AND c.status = 'pending_dean' AND p.college_id = v_college)
            OR (v_role = 'registrar' AND c.status = 'pending_registrar')
            OR (v_role = 'professor' AND c.proposed_by = v_actor))
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION refuse_direct_prerequisite_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.prereq_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Prerequisites and credits change only through their functions';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_subject_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_names text;
BEGIN
  SELECT string_agg(s.code, ', ' ORDER BY s.code) INTO v_names
    FROM subject_prerequisites sp
    JOIN subjects s ON s.id = sp.subject_id
   WHERE sp.prerequisite_id = OLD.id;
  IF v_names IS NOT NULL THEN
    RAISE EXCEPTION 'The subject % is a prerequisite of %. Remove it from those subjects first', OLD.code, v_names;
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  DELETE FROM subject_prerequisites WHERE subject_id = OLD.id;
  PERFORM set_config('app.prereq_write', 'off', true);
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION student_has_passed(p_student uuid, p_subject uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
           SELECT 1 FROM grades g
             JOIN grade_sheets gs ON gs.id = g.sheet_id
            WHERE g.student_id = p_student AND g.subject_id = p_subject
              AND g.outcome = 'passed' AND gs.status = 'approved')
      OR EXISTS (
           SELECT 1 FROM student_credits c
            WHERE c.student_id = p_student AND c.subject_id = p_subject AND c.status = 'approved')
$$;

CREATE OR REPLACE FUNCTION student_blocking_prerequisites(p_student uuid, p_subject uuid)
RETURNS TABLE (b_subject_id uuid, b_code text, b_title text, b_status text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.code::text, p.title::text,
         coalesce((SELECT g.outcome FROM grades g
                     JOIN grade_sheets gs ON gs.id = g.sheet_id
                    WHERE g.student_id = p_student AND g.subject_id = p.id AND gs.status = 'approved'
                    ORDER BY g.outcome_since DESC LIMIT 1), 'not_taken')
    FROM subject_prerequisites sp
    JOIN subjects p ON p.id = sp.prerequisite_id
   WHERE sp.subject_id = p_subject
     AND NOT student_has_passed(p_student, p.id)
   ORDER BY p.code
$$;

CREATE OR REPLACE FUNCTION subject_eligibility(p_student uuid, p_subject uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_blocked jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('registrar','dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'You cannot check eligibility';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student) THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM subjects WHERE id = p_subject) THEN
    RAISE EXCEPTION 'That subject was not found';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'subjectId', b.b_subject_id, 'code', b.b_code, 'title', b.b_title, 'status', b.b_status) ORDER BY b.b_code), '[]'::jsonb)
    INTO v_blocked
    FROM student_blocking_prerequisites(p_student, p_subject) b;

  RETURN jsonb_build_object('allowed', jsonb_array_length(v_blocked) = 0, 'blockedBy', v_blocked);
END;
$$;

CREATE OR REPLACE FUNCTION prerequisite_programs() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin','registrar','dean','college_secretary') THEN
    RAISE EXCEPTION 'You cannot read prerequisites';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name) ORDER BY p.code)
      FROM programs p
     WHERE v_role IN ('admin','registrar') OR p.college_id = app_college_id()
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION prerequisites_list(p_program uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin','registrar','dean','college_secretary') THEN
    RAISE EXCEPTION 'You cannot read prerequisites';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT program_in_my_college(p_program) THEN
    RAISE EXCEPTION 'That program is not in your college';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'subjectId', s.id,
             'code', s.code,
             'title', s.title,
             'yearLevel', s.year_level,
             'semester', s.semester,
             'prerequisites', coalesce((
               SELECT jsonb_agg(jsonb_build_object('subjectId', r.id, 'code', r.code, 'title', r.title) ORDER BY r.code)
                 FROM subject_prerequisites sp
                 JOIN subjects r ON r.id = sp.prerequisite_id
                WHERE sp.subject_id = s.id), '[]'::jsonb)
           ) ORDER BY s.year_level NULLS LAST, semester_rank(s.semester), s.code)
      FROM subjects s
     WHERE s.program_id = p_program
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION save_prerequisites(p_subject uuid, p_required uuid[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_sub subjects%ROWTYPE;
  v_req subjects%ROWTYPE;
  v_ids uuid[];
  v_id uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin','dean') THEN
    RAISE EXCEPTION 'Only Admin or the Dean of this college can set prerequisites';
  END IF;
  SELECT * INTO v_sub FROM subjects WHERE id = p_subject;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'That subject was not found';
  END IF;
  IF v_role = 'dean' AND NOT program_in_my_college(v_sub.program_id) THEN
    RAISE EXCEPTION 'Only the Dean of this college can set the prerequisites of this program';
  END IF;

  SELECT coalesce(array_agg(DISTINCT x), '{}'::uuid[]) INTO v_ids
    FROM unnest(coalesce(p_required, '{}'::uuid[])) AS x
   WHERE x IS NOT NULL;

  FOREACH v_id IN ARRAY v_ids LOOP
    SELECT * INTO v_req FROM subjects WHERE id = v_id;
    IF v_req.id IS NULL THEN
      RAISE EXCEPTION 'A required subject was not found';
    END IF;
    IF v_req.id = v_sub.id THEN
      RAISE EXCEPTION '% cannot require itself', v_sub.code;
    END IF;
    IF v_req.program_id <> v_sub.program_id THEN
      RAISE EXCEPTION '% is in another program. A prerequisite must be in the same program', v_req.code;
    END IF;
    IF v_req.year_level IS NULL OR v_sub.year_level IS NULL THEN
      RAISE EXCEPTION 'Set the year level of % and % first', v_sub.code, v_req.code;
    END IF;
    IF NOT (v_req.year_level < v_sub.year_level
            OR (v_req.year_level = v_sub.year_level AND semester_rank(v_req.semester) < semester_rank(v_sub.semester))) THEN
      RAISE EXCEPTION '% is not earlier in the curriculum than %', v_req.code, v_sub.code;
    END IF;
    IF EXISTS (
         WITH RECURSIVE up(id) AS (
           SELECT sp.prerequisite_id FROM subject_prerequisites sp WHERE sp.subject_id = v_id
           UNION
           SELECT sp.prerequisite_id FROM subject_prerequisites sp JOIN up ON sp.subject_id = up.id)
         SELECT 1 FROM up WHERE up.id = p_subject) THEN
      RAISE EXCEPTION '% already depends on %, so this would make a loop', v_req.code, v_sub.code;
    END IF;
  END LOOP;

  PERFORM set_config('app.prereq_write', 'on', true);
  DELETE FROM subject_prerequisites WHERE subject_id = p_subject AND NOT (prerequisite_id = ANY (v_ids));
  INSERT INTO subject_prerequisites (subject_id, prerequisite_id)
  SELECT p_subject, x FROM unnest(v_ids) AS x
  ON CONFLICT (subject_id, prerequisite_id) DO NOTHING;
  PERFORM set_config('app.prereq_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION credit_overview(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_program uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('registrar','dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'You cannot read credits';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students s JOIN applicants a ON a.id = s.applicant_id
   WHERE s.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;

  RETURN jsonb_build_object(
    'credits', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', c.id,
               'status', c.status,
               'code', sub.code,
               'title', sub.title,
               'reason', c.reason,
               'rejectedReason', c.rejected_reason,
               'recordedBy', (SELECT u.full_name FROM users u WHERE u.id = c.recorded_by),
               'recordedAt', c.recorded_at
             ) ORDER BY c.recorded_at)
        FROM student_credits c
        JOIN subjects sub ON sub.id = c.subject_id
       WHERE c.student_id = p_student), '[]'::jsonb),
    'options', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'subjectId', s.id, 'code', s.code, 'title', s.title, 'yearLevel', s.year_level
             ) ORDER BY s.year_level NULLS LAST, semester_rank(s.semester), s.code)
        FROM subjects s
       WHERE s.program_id = v_program
         AND NOT student_has_passed(p_student, s.id)
         AND NOT EXISTS (SELECT 1 FROM student_credits c WHERE c.student_id = p_student AND c.subject_id = s.id AND c.status = 'pending')
    ), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION record_credit(p_student uuid, p_subject uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_program uuid;
  v_sub subjects%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_id uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'Only the Dean or the College Secretary can record a credit';
  END IF;
  SELECT a.program_id INTO v_program
    FROM students s JOIN applicants a ON a.id = s.applicant_id
   WHERE s.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role IN ('dean','college_secretary') AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  SELECT * INTO v_sub FROM subjects WHERE id = p_subject;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'That subject was not found';
  END IF;
  IF v_sub.program_id <> v_program THEN
    RAISE EXCEPTION '% is not in the student''s program', v_sub.code;
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  IF student_has_passed(p_student, p_subject) THEN
    RAISE EXCEPTION 'The student has already passed or been credited %', v_sub.code;
  END IF;
  IF EXISTS (SELECT 1 FROM student_credits c WHERE c.student_id = p_student AND c.subject_id = p_subject AND c.status = 'pending') THEN
    RAISE EXCEPTION 'A credit for % is already waiting for the Registrar', v_sub.code;
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  INSERT INTO student_credits (student_id, subject_id, reason, recorded_by)
  VALUES (p_student, p_subject, v_reason, current_actor_id())
  RETURNING id INTO v_id;
  PERFORM set_config('app.prereq_write', 'off', true);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION credits_pending() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'You cannot read credits waiting for approval';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'id', c.id,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'program', p.code,
             'code', sub.code,
             'title', sub.title,
             'reason', c.reason,
             'recordedBy', (SELECT ru.full_name FROM users ru WHERE ru.id = c.recorded_by),
             'recordedAt', c.recorded_at
           ) ORDER BY c.recorded_at)
      FROM student_credits c
      JOIN students st ON st.id = c.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = a.program_id
      JOIN subjects sub ON sub.id = c.subject_id
     WHERE c.status = 'pending'
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION approve_credit(p_credit uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_credit student_credits%ROWTYPE;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can approve a credit';
  END IF;
  SELECT * INTO v_credit FROM student_credits WHERE id = p_credit FOR UPDATE;
  IF v_credit.id IS NULL OR v_credit.status <> 'pending' THEN
    RAISE EXCEPTION 'This credit is not waiting for approval';
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  UPDATE student_credits SET status = 'approved', decided_by = current_actor_id(), decided_at = now() WHERE id = p_credit;
  PERFORM set_config('app.prereq_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION reject_credit(p_credit uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_credit student_credits%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can reject a credit';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  SELECT * INTO v_credit FROM student_credits WHERE id = p_credit FOR UPDATE;
  IF v_credit.id IS NULL OR v_credit.status <> 'pending' THEN
    RAISE EXCEPTION 'This credit is not waiting for approval';
  END IF;

  PERFORM set_config('app.prereq_write', 'on', true);
  UPDATE student_credits
     SET status = 'rejected', decided_by = current_actor_id(), decided_at = now(), rejected_reason = v_reason
   WHERE id = p_credit;
  PERFORM set_config('app.prereq_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION student_load(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role     text := app_role();
  v_term     enrollment_term%ROWTYPE;
  v_program  uuid;
  v_number   text;
  v_name     text;
  v_code     text;
  v_section  uuid;
  v_label    text;
  v_locked   boolean;
  v_places   jsonb;
  v_subjects jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read a student''s load';
  END IF;
  SELECT a.program_id, st.student_number, u.full_name, p.code
    INTO v_program, v_number, v_name, v_code
    FROM students st
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
   WHERE st.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;

  SELECT ss.section_id, pr.code || ' ' || sec.year_level || sec.name
    INTO v_section, v_label
    FROM student_sections ss
    JOIN sections sec ON sec.id = ss.section_id
    JOIN programs pr ON pr.id = sec.program_id
   WHERE ss.student_id = p_student AND ss.school_year = v_term.school_year AND ss.semester = v_term.semester;

  v_locked := EXISTS (SELECT 1 FROM assessment_slips sl
                       WHERE sl.student_id = p_student AND sl.school_year = v_term.school_year AND sl.semester = v_term.semester);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'sectionId', sec.id,
           'label', pr.code || ' ' || sec.year_level || sec.name,
           'taken', (SELECT count(*) FROM student_sections x WHERE x.section_id = sec.id),
           'capacity', sec.capacity) ORDER BY sec.year_level, sec.name), '[]'::jsonb)
    INTO v_places
    FROM sections sec JOIN programs pr ON pr.id = sec.program_id
   WHERE sec.program_id = v_program AND sec.school_year = v_term.school_year AND sec.semester = v_term.semester;

  SELECT coalesce(jsonb_agg(q.item ORDER BY q.yl, q.sr, q.code), '[]'::jsonb) INTO v_subjects
    FROM (
      SELECT sub.year_level AS yl, semester_rank(sub.semester) AS sr, sub.code AS code,
             jsonb_build_object(
               'subjectId', sub.id,
               'code', sub.code,
               'title', sub.title,
               'yearLevel', sub.year_level,
               'semester', sub.semester,
               'status', CASE
                           WHEN cur.label IS NOT NULL THEN 'in_load'
                           WHEN student_has_passed(p_student, sub.id) THEN 'passed'
                           WHEN NOT subject_in_term(sub.semester, sub.offered_in_summer, v_term.semester) OR opt.n = 0 THEN 'not_offered'
                           WHEN blk.n > 0 THEN 'blocked'
                           ELSE 'allowed' END,
               'source', cur.source,
               'takenIn', cur.label,
               'blockedBy', blk.j,
               'options', opt.j) AS item
        FROM subjects sub
        LEFT JOIN LATERAL (
          SELECT pr.code || ' ' || sec.year_level || sec.name AS label, ls.source
            FROM student_subjects ls
            JOIN section_subjects x ON x.id = ls.section_subject_id
            JOIN sections sec ON sec.id = x.section_id
            JOIN programs pr ON pr.id = sec.program_id
           WHERE ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
             AND x.subject_id = sub.id
           LIMIT 1) cur ON true
        LEFT JOIN LATERAL (
          SELECT coalesce(jsonb_agg(jsonb_build_object('code', b.b_code, 'status', b.b_status) ORDER BY b.b_code), '[]'::jsonb) AS j,
                 count(*) AS n
            FROM student_blocking_prerequisites(p_student, sub.id) b) blk ON true
        LEFT JOIN LATERAL (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
                          'sectionId', o.id, 'label', o.label, 'taken', o.taken, 'capacity', o.capacity) ORDER BY o.label), '[]'::jsonb) AS j,
                 count(*) AS n
            FROM (
              SELECT sec.id, pr.code || ' ' || sec.year_level || sec.name AS label, sec.capacity,
                     (SELECT count(DISTINCT l2.student_id) FROM student_subjects l2
                        JOIN section_subjects y ON y.id = l2.section_subject_id
                       WHERE y.section_id = sec.id AND y.subject_id = sub.id) AS taken
                FROM sections sec JOIN programs pr ON pr.id = sec.program_id
               WHERE sec.program_id = v_program AND sec.school_year = v_term.school_year AND sec.semester = v_term.semester
                 AND EXISTS (SELECT 1 FROM section_subjects y WHERE y.section_id = sec.id AND y.subject_id = sub.id)
            ) o) opt ON true
       WHERE sub.program_id = v_program AND sub.year_level IS NOT NULL
    ) q;

  RETURN jsonb_build_object(
    'studentId', p_student,
    'studentNumber', v_number,
    'fullName', v_name,
    'programCode', v_code,
    'schoolYear', v_term.school_year,
    'semester', v_term.semester,
    'enrolled', v_section IS NOT NULL,
    'section', v_label,
    'locked', v_locked,
    'places', v_places,
    'subjects', v_subjects);
END;
$$;

CREATE OR REPLACE FUNCTION add_subject_to_load(p_student uuid, p_section uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_term    enrollment_term%ROWTYPE;
  v_program uuid;
  v_user    uuid;
  v_sec     sections%ROWTYPE;
  v_sub     subjects%ROWTYPE;
  v_block   text;
  v_taken   integer;
  v_clash   text;
  v_label   text;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary or the Dean can change a student''s load';
  END IF;

  SELECT a.program_id, a.user_id INTO v_program, v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;
  IF v_program IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = p_student AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'This student belongs to another college';
  END IF;

  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;

  PERFORM 1 FROM student_sections
   WHERE student_id = p_student AND school_year = v_term.school_year AND semester = v_term.semester
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Place the student in a section of the current term first';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips
              WHERE student_id = p_student AND school_year = v_term.school_year AND semester = v_term.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the load can no longer be changed';
  END IF;

  SELECT * INTO v_sec FROM sections WHERE id = p_section FOR UPDATE;
  IF v_sec.id IS NULL THEN
    RAISE EXCEPTION 'Section not found';
  END IF;
  IF v_sec.program_id <> v_program THEN
    RAISE EXCEPTION 'A subject can only be taken from a section of the student''s own program';
  END IF;
  IF (v_sec.school_year, v_sec.semester) IS DISTINCT FROM (v_term.school_year, v_term.semester) THEN
    RAISE EXCEPTION 'Only a section of the current term can be used';
  END IF;

  SELECT * INTO v_sub FROM subjects WHERE id = p_subject;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'Subject not found';
  END IF;
  IF v_sub.program_id <> v_program THEN
    RAISE EXCEPTION '% is not a subject of the student''s program', v_sub.code;
  END IF;
  IF NOT subject_in_term(v_sub.semester, v_sub.offered_in_summer, v_term.semester) THEN
    RAISE EXCEPTION '% is not offered in the % semester', v_sub.code, v_term.semester;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM section_subjects x WHERE x.section_id = p_section AND x.subject_id = p_subject) THEN
    RAISE EXCEPTION 'That section does not offer %', v_sub.code;
  END IF;
  IF EXISTS (SELECT 1 FROM student_subjects ls
               JOIN section_subjects x ON x.id = ls.section_subject_id
              WHERE ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
                AND x.subject_id = p_subject) THEN
    RAISE EXCEPTION 'The student already takes %', v_sub.code;
  END IF;
  IF student_has_passed(p_student, p_subject) THEN
    RAISE EXCEPTION 'The student already passed or was credited %', v_sub.code;
  END IF;

  SELECT string_agg(b.b_code || ' (' || replace(b.b_status, '_', ' ') || ')', ', ' ORDER BY b.b_code) INTO v_block
    FROM student_blocking_prerequisites(p_student, p_subject) b;
  IF v_block IS NOT NULL THEN
    RAISE EXCEPTION '% needs a passed prerequisite: %', v_sub.code, v_block;
  END IF;

  SELECT pr.code || ' ' || v_sec.year_level || v_sec.name INTO v_label FROM programs pr WHERE pr.id = v_sec.program_id;
  SELECT count(DISTINCT l2.student_id)::integer INTO v_taken
    FROM student_subjects l2 JOIN section_subjects y ON y.id = l2.section_subject_id
   WHERE y.section_id = p_section AND y.subject_id = p_subject;
  IF v_taken >= v_sec.capacity THEN
    RAISE EXCEPTION '% has no free seat for % (% of %)', v_label, v_sub.code, v_taken, v_sec.capacity;
  END IF;

  SELECT cs.code INTO v_clash
    FROM student_subjects ls
    JOIN section_subjects a1 ON a1.id = ls.section_subject_id
    JOIN subjects cs ON cs.id = a1.subject_id
    JOIN section_subjects n ON n.section_id = p_section AND n.subject_id = p_subject
   WHERE ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
     AND a1.day_of_week IS NOT NULL AND n.day_of_week = a1.day_of_week
     AND a1.start_time IS NOT NULL AND n.start_time IS NOT NULL
     AND a1.start_time < n.end_time AND n.start_time < a1.end_time
   LIMIT 1;
  IF v_clash IS NOT NULL THEN
    RAISE EXCEPTION '% clashes in time with % already in the load', v_sub.code, v_clash;
  END IF;

  PERFORM set_config('app.load_write', 'on', true);
  INSERT INTO student_subjects (student_id, school_year, semester, section_subject_id, source, added_by)
  SELECT p_student, v_term.school_year, v_term.semester, x.id, 'added', current_actor_id()
    FROM section_subjects x
   WHERE x.section_id = p_section AND x.subject_id = p_subject;
  PERFORM set_config('app.load_write', 'off', true);

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'load_changed', 'Your subjects changed',
          v_sub.code || ' in ' || v_label || ' was added to your subjects. Your college is preparing your schedule.');
END;
$$;

CREATE OR REPLACE FUNCTION remove_subject_from_load(p_student uuid, p_subject uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role    text := app_role();
  v_term    enrollment_term%ROWTYPE;
  v_user    uuid;
  v_code    text;
  v_rows    integer;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary or the Dean can change a student''s load';
  END IF;
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Student not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'This student belongs to another college';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF EXISTS (SELECT 1 FROM assessment_slips
              WHERE student_id = p_student AND school_year = v_term.school_year AND semester = v_term.semester) THEN
    RAISE EXCEPTION 'The assessment slip was already issued, so the load can no longer be changed';
  END IF;

  SELECT code INTO v_code FROM subjects WHERE id = p_subject;
  DELETE FROM student_subjects ls
   USING section_subjects x
   WHERE x.id = ls.section_subject_id AND x.subject_id = p_subject
     AND ls.student_id = p_student AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester
     AND ls.source = 'added';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'That subject was not added by staff, so it stays in the load';
  END IF;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'load_changed', 'Your subjects changed',
          v_code || ' was removed from your subjects. Your college is preparing your schedule.');
END;
$$;

CREATE OR REPLACE FUNCTION refuse_direct_term_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.term_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Term results change only through closing a term';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION has_enrollment_after(p_student uuid, p_year text, p_semester text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM student_sections ss
     WHERE ss.student_id = p_student
       AND (ss.school_year > p_year
            OR (ss.school_year = p_year AND semester_rank(ss.semester) > semester_rank(p_semester))))
$$;

CREATE OR REPLACE FUNCTION term_missing_sheets() RETURNS TABLE (m_label text, m_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (p.code || ' ' || sec.year_level || sec.name)::text, sub.code::text
    FROM enrollment_term t
    JOIN sections sec ON sec.school_year = t.school_year AND sec.semester = t.semester
    JOIN programs p ON p.id = sec.program_id
    JOIN (SELECT DISTINCT section_id, subject_id FROM section_subjects) x ON x.section_id = sec.id
    JOIN subjects sub ON sub.id = x.subject_id
   WHERE EXISTS (SELECT 1 FROM student_subjects ls
                   JOIN section_subjects y ON y.id = ls.section_subject_id
                  WHERE y.section_id = sec.id AND y.subject_id = sub.id)
     AND NOT EXISTS (SELECT 1 FROM grade_sheets gs
                      WHERE gs.section_id = sec.id AND gs.subject_id = sub.id AND gs.status = 'approved')
   ORDER BY 1, 2
$$;

CREATE OR REPLACE FUNCTION term_close_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_term    enrollment_term%ROWTYPE;
  v_closed  boolean;
  v_total   integer;
  v_missing jsonb;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can see the term status';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('term', NULL, 'closed', false, 'enrolled', 0, 'missing', '[]'::jsonb, 'missingTotal', 0);
  END IF;

  v_closed := EXISTS (SELECT 1 FROM term_closures c
                       WHERE c.school_year = v_term.school_year AND c.semester = v_term.semester);
  SELECT count(*) INTO v_total FROM term_missing_sheets();
  SELECT coalesce(jsonb_agg(jsonb_build_object('label', q.m_label, 'code', q.m_code) ORDER BY q.m_label, q.m_code), '[]'::jsonb)
    INTO v_missing
    FROM (SELECT m.m_label, m.m_code FROM term_missing_sheets() m ORDER BY m.m_label, m.m_code LIMIT 5) q;

  RETURN jsonb_build_object(
    'term', jsonb_build_object('schoolYear', v_term.school_year, 'semester', v_term.semester),
    'closed', v_closed,
    'enrolled', (SELECT count(*) FROM student_sections ss
                  WHERE ss.school_year = v_term.school_year AND ss.semester = v_term.semester),
    'missing', v_missing,
    'missingTotal', v_total);
END;
$$;

CREATE OR REPLACE FUNCTION review_students() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read the review list';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(q.item ORDER BY q.program_code, q.student_number)
      FROM (
        SELECT p.code AS program_code, st.student_number,
               jsonb_build_object(
                 'kind', 'review',
                 'studentId', st.id,
                 'studentNumber', st.student_number,
                 'fullName', u.full_name,
                 'programCode', p.code,
                 'yearLevel', tr.year_level,
                 'schoolYear', tr.school_year,
                 'semester', tr.semester,
                 'reason', coalesce(tr.reason, '')
               ) AS item
          FROM term_results tr
          JOIN students st ON st.id = tr.student_id
          JOIN applicants a ON a.id = st.applicant_id
          JOIN users u ON u.id = a.user_id
          JOIN programs p ON p.id = tr.program_id
         WHERE tr.result = 'review'
           AND a.withdrawn_at IS NULL
           AND NOT has_enrollment_after(tr.student_id, tr.school_year, tr.semester)
           AND (v_role = 'admin' OR program_in_my_college(tr.program_id))
           AND NOT EXISTS (SELECT 1 FROM leaves l
                            WHERE l.student_id = tr.student_id
                              AND (l.status IN ('approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL)))
        UNION ALL
        SELECT p.code, st.student_number,
               jsonb_build_object(
                 'kind', 'leave',
                 'studentId', st.id,
                 'studentNumber', st.student_number,
                 'fullName', u.full_name,
                 'programCode', p.code,
                 'yearLevel', coalesce(lastsec.year_level, 0),
                 'schoolYear', l.return_year,
                 'semester', l.return_semester,
                 'reason', CASE WHEN leave_terms_used(st.id) >= 4
                                THEN 'Two years of leave used'
                                ELSE 'Returning from leave' END
               )
          FROM leaves l
          JOIN students st ON st.id = l.student_id
          JOIN applicants a ON a.id = st.applicant_id
          JOIN users u ON u.id = a.user_id
          JOIN programs p ON p.id = a.program_id
          LEFT JOIN LATERAL (
            SELECT sec.year_level
              FROM student_sections ss JOIN sections sec ON sec.id = ss.section_id
             WHERE ss.student_id = st.id
             ORDER BY ss.school_year DESC, semester_rank(ss.semester) DESC
             LIMIT 1) lastsec ON true
         WHERE l.status = 'ended' AND l.returned_at IS NULL
           AND a.withdrawn_at IS NULL
           AND (v_role = 'admin' OR p.college_id = app_college_id())
      ) q
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION completed_students() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can read the completed students';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'studentId', st.id,
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'schoolYear', tr.school_year,
             'semester', tr.semester
           ) ORDER BY tr.school_year DESC, semester_rank(tr.semester) DESC, p.code, st.student_number)
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = tr.program_id
     WHERE tr.result = 'completed' AND a.withdrawn_at IS NULL
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION my_needs_advising() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
     WHERE tr.student_id = my_student_id()
       AND tr.result = 'review'
       AND a.withdrawn_at IS NULL
       AND NOT has_enrollment_after(tr.student_id, tr.school_year, tr.semester))
$$;

CREATE OR REPLACE FUNCTION close_term() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_term      enrollment_term%ROWTYPE;
  v_total     integer;
  v_names     text;
  r           record;
  v_counted   integer;
  v_reason    text;
  v_last_year integer;
  v_last_sem  text;
  v_result    text;
  v_promote   integer := 0;
  v_review    integer := 0;
  v_completed integer := 0;
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can close a term';
  END IF;

  SELECT * INTO v_term FROM enrollment_term FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF EXISTS (SELECT 1 FROM term_closures c
              WHERE c.school_year = v_term.school_year AND c.semester = v_term.semester) THEN
    RAISE EXCEPTION 'This term is already closed';
  END IF;

  PERFORM lapse_incomplete_grades();

  SELECT count(*) INTO v_total FROM term_missing_sheets();
  IF v_total > 0 THEN
    SELECT string_agg(q.m_label || ' ' || q.m_code, ', ' ORDER BY q.m_label, q.m_code) INTO v_names
      FROM (SELECT m.m_label, m.m_code FROM term_missing_sheets() m ORDER BY m.m_label, m.m_code LIMIT 5) q;
    RAISE EXCEPTION 'Grades are not approved yet for: %',
      v_names || CASE WHEN v_total > 5 THEN ' and ' || (v_total - 5) || ' more' ELSE '' END;
  END IF;

  PERFORM set_config('app.term_write', 'on', true);
  INSERT INTO term_closures (school_year, semester, closed_by)
  VALUES (v_term.school_year, v_term.semester, current_actor_id());

  IF v_term.semester <> 'summer' THEN
    FOR r IN
      SELECT ss.student_id, ss.section_id, sec.program_id, sec.year_level, sec.name
        FROM student_sections ss
        JOIN sections sec ON sec.id = ss.section_id
        JOIN students st ON st.id = ss.student_id
        JOIN applicants a ON a.id = st.applicant_id
       WHERE ss.school_year = v_term.school_year AND ss.semester = v_term.semester
         AND a.withdrawn_at IS NULL
       ORDER BY st.student_number
    LOOP

      SELECT count(*),
             string_agg(
               CASE coalesce(g.outcome, 'none')
                 WHEN 'incomplete' THEN 'Incomplete in ' || s.code
                 WHEN 'failed'     THEN 'Failed ' || s.code
                 WHEN 'dropped'    THEN 'Dropped ' || s.code
                 ELSE 'No grade in ' || s.code
               END, '; ' ORDER BY s.code)
             FILTER (WHERE coalesce(g.outcome, 'none') <> 'passed')
        INTO v_counted, v_reason
        FROM (SELECT DISTINCT y.section_id, y.subject_id
                FROM student_subjects ls
                JOIN section_subjects y ON y.id = ls.section_subject_id
               WHERE ls.student_id = r.student_id
                 AND ls.school_year = v_term.school_year AND ls.semester = v_term.semester) d
        JOIN subjects s ON s.id = d.subject_id
        LEFT JOIN grades g ON g.student_id = r.student_id AND g.section_id = d.section_id AND g.subject_id = s.id
                          AND EXISTS (SELECT 1 FROM grade_sheets gs WHERE gs.id = g.sheet_id AND gs.status = 'approved');

      SELECT max(sub.year_level) INTO v_last_year FROM subjects sub WHERE sub.program_id = r.program_id;
      v_last_sem := CASE WHEN EXISTS (SELECT 1 FROM subjects sub
                                       WHERE sub.program_id = r.program_id AND sub.year_level = v_last_year
                                         AND sub.semester = '2nd')
                         THEN '2nd' ELSE '1st' END;

      IF v_counted = 0 THEN
        v_result := 'review';
        v_reason := 'The student has no subjects this term';
      ELSIF v_reason IS NOT NULL THEN
        v_result := 'review';
      ELSIF v_last_year IS NOT NULL AND r.year_level >= v_last_year AND v_term.semester = v_last_sem THEN
        v_result := 'completed';
        v_reason := NULL;
      ELSE
        v_result := 'promote';
        v_reason := NULL;
      END IF;

      INSERT INTO term_results (school_year, semester, student_id, program_id, year_level, section_name, result, reason)
      VALUES (v_term.school_year, v_term.semester, r.student_id, r.program_id, r.year_level, r.name, v_result, v_reason);

      IF v_result = 'promote' THEN
        v_promote := v_promote + 1;
      ELSIF v_result = 'review' THEN
        v_review := v_review + 1;
      ELSE
        v_completed := v_completed + 1;
      END IF;
    END LOOP;
  END IF;
  PERFORM set_config('app.term_write', 'off', true);

  RETURN jsonb_build_object('promote', v_promote, 'review', v_review, 'completed', v_completed);
END;
$$;

CREATE OR REPLACE FUNCTION open_term(p_year text, p_semester text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_prev_year  text;
  v_prev_sem   text;
  v_closure    term_closures%ROWTYPE;
  r            record;
  v_next_year  integer;
  v_sec_id     uuid;
  v_sec_name   varchar;
  v_term_text  text;
BEGIN
  IF p_semester NOT IN ('1st','2nd') THEN
    RETURN;
  END IF;
  SELECT pr.prev_year, pr.prev_semester INTO v_prev_year, v_prev_sem FROM previous_regular_term(p_year, p_semester) pr;
  IF v_prev_year IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_closure FROM term_closures c
   WHERE c.school_year = v_prev_year AND c.semester = v_prev_sem
     FOR UPDATE;
  IF NOT FOUND OR v_closure.opened_at IS NOT NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('app.term_write', 'on', true);

  IF p_semester = '2nd' THEN
    INSERT INTO sections (program_id, name, year_level, capacity, school_year, semester)
    SELECT s.program_id, s.name, s.year_level, s.capacity, p_year, p_semester
      FROM sections s
     WHERE s.school_year = v_prev_year AND s.semester = v_prev_sem
    ON CONFLICT ON CONSTRAINT sections_term_name_key DO NOTHING;
  ELSE
    INSERT INTO sections (program_id, name, year_level, capacity, school_year, semester)
    SELECT x.program_id, x.name, x.year_level, x.capacity, p_year, p_semester
      FROM (
        SELECT s.program_id, s.name, 1 AS year_level, s.capacity
          FROM sections s
         WHERE s.school_year = v_prev_year AND s.semester = v_prev_sem AND s.year_level = 1
        UNION
        SELECT s.program_id, s.name, s.year_level + 1, s.capacity
          FROM sections s
         WHERE s.school_year = v_prev_year AND s.semester = v_prev_sem
           AND s.year_level + 1 <= coalesce((SELECT max(sub.year_level) FROM subjects sub WHERE sub.program_id = s.program_id), 0)
      ) x
    ON CONFLICT ON CONSTRAINT sections_term_name_key DO NOTHING;
  END IF;

  v_term_text := CASE p_semester WHEN '1st' THEN '1st semester' ELSE '2nd semester' END || ' of school year ' || p_year;

  FOR r IN
    SELECT tr.student_id, tr.program_id, tr.year_level, tr.section_name, a.user_id, a.withdrawn_at, p.code AS program_code
      FROM term_results tr
      JOIN students st ON st.id = tr.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN programs p ON p.id = tr.program_id
     WHERE tr.school_year = v_prev_year AND tr.semester = v_prev_sem
       AND tr.result = 'promote' AND tr.placed_at IS NULL
     ORDER BY st.student_number
  LOOP
    IF r.withdrawn_at IS NOT NULL THEN
      CONTINUE;
    END IF;

    IF EXISTS (SELECT 1 FROM leaves l
                WHERE l.student_id = r.student_id AND l.status IN ('approved','active')
                  AND leave_covers_term(l.start_year, l.start_semester, l.return_year, l.return_semester, p_year, p_semester)) THEN
      UPDATE term_results SET reason = 'On leave of absence'
       WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
      CONTINUE;
    END IF;

    v_next_year := CASE WHEN v_prev_sem = '2nd' THEN r.year_level + 1 ELSE r.year_level END;

    IF EXISTS (SELECT 1 FROM student_sections x
                WHERE x.student_id = r.student_id AND x.school_year = p_year AND x.semester = p_semester) THEN
      UPDATE term_results SET placed_at = now()
       WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
      CONTINUE;
    END IF;

    v_sec_id := NULL;
    v_sec_name := NULL;
    SELECT sec.id, sec.name INTO v_sec_id, v_sec_name
      FROM sections sec
     WHERE sec.program_id = r.program_id AND sec.year_level = v_next_year
       AND sec.school_year = p_year AND sec.semester = p_semester
       AND (SELECT count(*) FROM student_sections x WHERE x.section_id = sec.id) < sec.capacity
     ORDER BY (sec.name = r.section_name) DESC, sec.name, sec.id
     LIMIT 1
       FOR UPDATE OF sec;

    IF v_sec_id IS NULL THEN
      UPDATE term_results
         SET result = 'review',
             reason = 'No section with a free seat in ' || r.program_code || ' year ' || v_next_year
       WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
      CONTINUE;
    END IF;

    INSERT INTO student_sections (student_id, section_id) VALUES (r.student_id, v_sec_id);
    UPDATE term_results SET placed_at = now()
     WHERE school_year = v_prev_year AND semester = v_prev_sem AND student_id = r.student_id;
    INSERT INTO notifications (user_id, kind, title, message)
    VALUES (r.user_id, 'section_placed', 'Your section',
            'You are placed in ' || r.program_code || ' ' || v_next_year || v_sec_name || ' for the ' || v_term_text
            || '. Your college is preparing your schedule.');
  END LOOP;

  UPDATE term_closures SET opened_at = now()
   WHERE school_year = v_prev_year AND semester = v_prev_sem;
  PERFORM set_config('app.term_write', 'off', true);
END;
$$;

CREATE OR REPLACE FUNCTION after_term_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM open_term(NEW.school_year, NEW.semester);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION refuse_direct_leave_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('app.leave_write', true), '') <> 'on' THEN
    RAISE EXCEPTION 'A leave of absence changes only through the leave functions';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION leave_terms_used(p_student uuid) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(sum(l.terms), 0)::integer
    FROM leaves l
   WHERE l.student_id = p_student AND l.status IN ('approved','active','ended')
$$;

CREATE OR REPLACE FUNCTION leave_json(l leaves) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'id', l.id, 'status', l.status,
    'startYear', l.start_year, 'startSemester', l.start_semester, 'terms', l.terms,
    'returnYear', l.return_year, 'returnSemester', l.return_semester,
    'reason', l.reason, 'decisionNote', l.decision_note,
    'returned', l.returned_at IS NOT NULL)
$$;

CREATE OR REPLACE FUNCTION leave_guard_enrollment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  l leaves%ROWTYPE;
BEGIN
  SELECT * INTO l FROM leaves x
   WHERE x.student_id = NEW.student_id AND x.status IN ('approved','active')
     AND leave_covers_term(x.start_year, x.start_semester, x.return_year, x.return_semester, NEW.school_year, NEW.semester);
  IF FOUND THEN
    RAISE EXCEPTION 'This student is on leave of absence until the %',
      term_text(l.return_year, l.return_semester);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION run_leave_catch_up() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_term enrollment_term%ROWTYPE;
  r      record;
  v_n    integer := 0;
BEGIN
  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  PERFORM set_config('app.leave_write', 'on', true);

  FOR r IN
    SELECT l.id, a.user_id
      FROM leaves l
      JOIN students st ON st.id = l.student_id
      JOIN applicants a ON a.id = st.applicant_id
     WHERE l.status = 'approved' AND a.withdrawn_at IS NULL
       AND term_order(v_term.school_year, v_term.semester) >= term_order(l.start_year, l.start_semester)
       FOR UPDATE OF l
  LOOP
    UPDATE leaves SET status = 'active', activated_at = now() WHERE id = r.id;
    UPDATE users SET is_active = false WHERE id = r.user_id;
    v_n := v_n + 1;
  END LOOP;

  FOR r IN
    SELECT l.id
      FROM leaves l
     WHERE l.status = 'active'
       AND term_order(v_term.school_year, v_term.semester) >= term_order(l.return_year, l.return_semester)
       FOR UPDATE OF l
  LOOP
    UPDATE leaves SET status = 'ended', ended_at = now() WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;

  PERFORM set_config('app.leave_write', 'off', true);
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION leave_catch_up() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','dean','college_secretary','admin') THEN
    RAISE EXCEPTION 'You cannot run the leave catch up';
  END IF;
  RETURN run_leave_catch_up();
END;
$$;

CREATE OR REPLACE FUNCTION after_term_changed_leaves() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM run_leave_catch_up();
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION leave_after_enrollment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  l      leaves%ROWTYPE;
  v_user uuid;
BEGIN
  SELECT * INTO l FROM leaves x
   WHERE x.student_id = NEW.student_id AND x.status = 'ended' AND x.returned_at IS NULL
     FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = NEW.student_id;

  PERFORM set_config('app.leave_write', 'on', true);
  UPDATE leaves
     SET returned_at = now(), returned_year = NEW.school_year, returned_semester = NEW.semester,
         readmitted_by = current_actor_id()
   WHERE id = l.id;
  PERFORM set_config('app.leave_write', 'off', true);

  UPDATE users SET is_active = true WHERE id = v_user;
  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'readmitted', 'Welcome back',
          'Your account is active again and your readmission slip is ready. Your college is preparing your schedule for the '
          || term_text(NEW.school_year, NEW.semester) || '.');
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION record_leave(
  p_student uuid, p_year text, p_semester text, p_terms integer, p_reason text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role   text := app_role();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_term   enrollment_term%ROWTYPE;
  v_ret    record;
  v_used   integer;
  v_id     uuid;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'Only the College Secretary or the Dean can record a leave of absence';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student) THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  IF EXISTS (SELECT 1 FROM students st JOIN applicants a ON a.id = st.applicant_id
              WHERE st.id = p_student AND a.withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This student has withdrawn';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Enter the reason';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  IF p_semester IS NULL OR p_semester NOT IN ('1st','2nd') OR p_year IS NULL OR p_year !~ '^[0-9]{4}-[0-9]{4}$' THEN
    RAISE EXCEPTION 'A leave starts at the 1st or 2nd semester of a school year';
  END IF;
  IF p_terms IS NULL OR p_terms NOT IN (1, 2) THEN
    RAISE EXCEPTION 'A leave lasts one or two terms, one academic year at most';
  END IF;

  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF term_order(p_year, p_semester) < term_order(v_term.school_year, v_term.semester) THEN
    RAISE EXCEPTION 'A leave cannot start before the current term';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM student_sections WHERE student_id = p_student) THEN
    RAISE EXCEPTION 'This student has no enrollment yet, so there is nothing to leave. A new student can withdraw instead';
  END IF;
  IF EXISTS (SELECT 1 FROM student_sections ss
              WHERE ss.student_id = p_student
                AND term_order(ss.school_year, ss.semester) >= term_order(p_year, p_semester)) THEN
    RAISE EXCEPTION 'The student is already placed in the % or later. Choose a later first term',
      term_text(p_year, p_semester);
  END IF;
  IF EXISTS (SELECT 1 FROM leaves l WHERE l.student_id = p_student
              AND (l.status IN ('requested','approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL))) THEN
    RAISE EXCEPTION 'This student already has a leave that is not finished';
  END IF;
  v_used := leave_terms_used(p_student);
  IF v_used + p_terms > 4 THEN
    RAISE EXCEPTION 'This leave would pass two academic years in all. The student has used % of 4 terms', v_used;
  END IF;

  SELECT r.return_year, r.return_semester INTO v_ret FROM leave_return_term(p_year, p_semester, p_terms) r;

  PERFORM set_config('app.leave_write', 'on', true);
  INSERT INTO leaves (student_id, start_year, start_semester, terms, return_year, return_semester, reason, recorded_by)
  VALUES (p_student, p_year, p_semester, p_terms, v_ret.return_year, v_ret.return_semester, v_reason, current_actor_id())
  RETURNING id INTO v_id;
  PERFORM set_config('app.leave_write', 'off', true);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION decide_leave(p_leave uuid, p_approve boolean, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  l      leaves%ROWTYPE;
  v_term enrollment_term%ROWTYPE;
  v_user uuid;
  v_used integer;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean can decide a leave of absence';
  END IF;
  SELECT * INTO l FROM leaves WHERE id = p_leave FOR UPDATE;
  IF l.id IS NULL OR l.status <> 'requested' THEN
    RAISE EXCEPTION 'This leave is not waiting for a decision';
  END IF;
  IF v_role = 'dean' AND NOT student_in_my_college(l.student_id) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  IF v_note IS NOT NULL AND length(v_note) > 500 THEN
    RAISE EXCEPTION 'The reason is longer than 500 characters';
  END IF;
  SELECT a.user_id INTO v_user FROM students st JOIN applicants a ON a.id = st.applicant_id WHERE st.id = l.student_id;

  IF NOT p_approve THEN
    IF v_note IS NULL THEN
      RAISE EXCEPTION 'Enter the reason';
    END IF;
    PERFORM set_config('app.leave_write', 'on', true);
    UPDATE leaves SET status = 'rejected', decided_by = current_actor_id(), decided_at = now(), decision_note = v_note
     WHERE id = l.id;
    PERFORM set_config('app.leave_write', 'off', true);
    IF l.recorded_by IS NOT NULL THEN
      INSERT INTO notifications (user_id, kind, title, message)
      VALUES (l.recorded_by, 'leave_rejected', 'Leave of absence not approved',
              'The leave from the ' || term_text(l.start_year, l.start_semester) || ' was not approved: ' || v_note);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO v_term FROM enrollment_term;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The school year and semester are not set. Ask Admin to set them';
  END IF;
  IF term_order(l.start_year, l.start_semester) < term_order(v_term.school_year, v_term.semester) THEN
    RAISE EXCEPTION 'The first term of this leave has passed. Reject it and record a new one';
  END IF;
  IF EXISTS (SELECT 1 FROM student_sections ss
              WHERE ss.student_id = l.student_id
                AND term_order(ss.school_year, ss.semester) >= term_order(l.start_year, l.start_semester)) THEN
    RAISE EXCEPTION 'The student is already placed in the % or later. Reject it and record a later start',
      term_text(l.start_year, l.start_semester);
  END IF;
  v_used := leave_terms_used(l.student_id);
  IF v_used + l.terms > 4 THEN
    RAISE EXCEPTION 'This leave would pass two academic years in all. The student has used % of 4 terms', v_used;
  END IF;

  PERFORM set_config('app.leave_write', 'on', true);
  UPDATE leaves SET status = 'approved', decided_by = current_actor_id(), decided_at = now(), decision_note = v_note
   WHERE id = l.id;
  PERFORM set_config('app.leave_write', 'off', true);

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (v_user, 'leave_approved', 'Leave of absence approved',
          'Your leave of absence starts with the ' || term_text(l.start_year, l.start_semester)
          || ' and you return in the ' || term_text(l.return_year, l.return_semester)
          || '. Your account is deactivated while you are on leave. Your college builds your subjects when you return.');

  PERFORM run_leave_catch_up();
END;
$$;

CREATE OR REPLACE FUNCTION leave_overview(p_student uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
  v_term enrollment_term%ROWTYPE;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('college_secretary','dean','admin') THEN
    RAISE EXCEPTION 'You cannot read leaves of absence';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student) THEN
    RAISE EXCEPTION 'That student was not found';
  END IF;
  IF v_role <> 'admin' AND NOT student_in_my_college(p_student) THEN
    RAISE EXCEPTION 'That student is not in your college';
  END IF;
  SELECT * INTO v_term FROM enrollment_term;
  RETURN jsonb_build_object(
    'term', CASE WHEN v_term.school_year IS NULL THEN NULL
                 ELSE jsonb_build_object('schoolYear', v_term.school_year, 'semester', v_term.semester) END,
    'used', leave_terms_used(p_student),
    'hasEnrollment', EXISTS (SELECT 1 FROM student_sections WHERE student_id = p_student),
    'open', EXISTS (SELECT 1 FROM leaves l WHERE l.student_id = p_student
                     AND (l.status IN ('requested','approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL))),
    'leaves', coalesce((SELECT jsonb_agg(leave_json(l) ORDER BY l.recorded_at) FROM leaves l WHERE l.student_id = p_student), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION leave_requests() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := app_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('dean','admin') THEN
    RAISE EXCEPTION 'Only the Dean can read leaves waiting for approval';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(leave_json(l) || jsonb_build_object(
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'usedTerms', leave_terms_used(l.student_id),
             'recordedBy', (SELECT ru.full_name FROM users ru WHERE ru.id = l.recorded_by),
             'recordedAt', l.recorded_at
           ) ORDER BY l.recorded_at)
      FROM leaves l
      JOIN students st ON st.id = l.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = a.program_id
     WHERE l.status = 'requested' AND a.withdrawn_at IS NULL
       AND (v_role = 'admin' OR p.college_id = app_college_id())
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION students_on_leave() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar can read the students on leave';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(leave_json(l) || jsonb_build_object(
             'studentNumber', st.student_number,
             'fullName', u.full_name,
             'programCode', p.code,
             'approvedBy', (SELECT du.full_name FROM users du WHERE du.id = l.decided_by)
           ) ORDER BY l.return_year, semester_rank(l.return_semester), st.student_number)
      FROM leaves l
      JOIN students st ON st.id = l.student_id
      JOIN applicants a ON a.id = st.applicant_id
      JOIN users u ON u.id = a.user_id
      JOIN programs p ON p.id = a.program_id
     WHERE (l.status IN ('approved','active') OR (l.status = 'ended' AND l.returned_at IS NULL))
       AND a.withdrawn_at IS NULL
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION my_leave() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT leave_json(l)
    FROM leaves l
   WHERE l.student_id = my_student_id() AND l.status = 'approved'
   LIMIT 1
$$;

CREATE OR REPLACE FUNCTION my_readmission() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
           'studentNumber', st.student_number,
           'fullName', u.full_name,
           'programCode', p.code,
           'programName', p.name,
           'section', (SELECT pr.code || ' ' || sec.year_level || sec.name
                         FROM student_sections ss
                         JOIN sections sec ON sec.id = ss.section_id
                         JOIN programs pr ON pr.id = sec.program_id
                        WHERE ss.student_id = st.id AND ss.school_year = l.returned_year AND ss.semester = l.returned_semester),
           'startYear', l.start_year, 'startSemester', l.start_semester, 'terms', l.terms,
           'returnYear', l.return_year, 'returnSemester', l.return_semester,
           'returnedYear', l.returned_year, 'returnedSemester', l.returned_semester,
           'returnedAt', l.returned_at,
           'approvedBy', (SELECT du.full_name FROM users du WHERE du.id = l.decided_by),
           'readmittedBy', (SELECT ru.full_name FROM users ru WHERE ru.id = l.readmitted_by))
    FROM leaves l
    JOIN students st ON st.id = l.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
   WHERE st.id = my_student_id() AND l.returned_at IS NOT NULL
   ORDER BY l.returned_at DESC
   LIMIT 1
$$;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_programs_updated_at BEFORE UPDATE ON programs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_applicants_updated_at BEFORE UPDATE ON applicants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_visit_slots_updated_at BEFORE UPDATE ON visit_slots
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_visit_bookings_updated_at BEFORE UPDATE ON visit_bookings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_sections_updated_at BEFORE UPDATE ON sections
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_payments_updated_at BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_programs_payment_setting AFTER INSERT ON programs
    FOR EACH ROW EXECUTE FUNCTION create_program_payment_setting();
CREATE TRIGGER trg_payment_setting_stamp BEFORE UPDATE ON program_payment_settings
    FOR EACH ROW EXECUTE FUNCTION stamp_payment_setting();

CREATE TRIGGER trg_enrollment_term_stamp BEFORE INSERT OR UPDATE ON enrollment_term
    FOR EACH ROW EXECUTE FUNCTION stamp_payment_setting();

CREATE TRIGGER trg_students_promote BEFORE INSERT ON students
    FOR EACH ROW EXECUTE FUNCTION promote_applicant_to_student();
CREATE TRIGGER trg_students_flip_role AFTER INSERT ON students
    FOR EACH ROW EXECUTE FUNCTION flip_user_to_student();
CREATE TRIGGER trg_students_no_number_edit BEFORE UPDATE ON students
    FOR EACH ROW EXECUTE FUNCTION prevent_student_number_edit();

CREATE TRIGGER trg_students_place AFTER INSERT ON students
    FOR EACH ROW EXECUTE FUNCTION trg_place_new_student();

CREATE TRIGGER trg_applicants_withdrawal BEFORE INSERT OR UPDATE ON applicants
    FOR EACH ROW EXECUTE FUNCTION enforce_withdrawal_columns();

CREATE TRIGGER trg_documents_open BEFORE INSERT OR UPDATE OR DELETE ON documents
    FOR EACH ROW EXECUTE FUNCTION enforce_documents_open();

CREATE TRIGGER trg_visit_bookings_capacity BEFORE INSERT OR UPDATE OF slot_id ON visit_bookings
    FOR EACH ROW EXECUTE FUNCTION enforce_booking_capacity();
CREATE TRIGGER trg_visit_slots_guard BEFORE UPDATE ON visit_slots
    FOR EACH ROW EXECUTE FUNCTION enforce_slot_guard();
CREATE TRIGGER trg_mass_reschedules_gate BEFORE INSERT ON mass_reschedules
    FOR EACH ROW EXECUTE FUNCTION enforce_mass_reschedule_gate();
CREATE TRIGGER trg_reschedule_requests_gate BEFORE INSERT OR UPDATE ON reschedule_requests
    FOR EACH ROW EXECUTE FUNCTION enforce_reschedule_request_gate();

CREATE TRIGGER trg_subjects_semester BEFORE INSERT ON subjects
    FOR EACH ROW EXECUTE FUNCTION set_subject_semester();
CREATE TRIGGER trg_subjects_add_to_sections AFTER INSERT ON subjects
    FOR EACH ROW EXECUTE FUNCTION add_subject_to_draft_sections();
CREATE TRIGGER trg_subjects_laboratory_added AFTER UPDATE OF has_laboratory ON subjects
    FOR EACH ROW WHEN (NEW.has_laboratory AND NOT OLD.has_laboratory)
    EXECUTE FUNCTION add_subject_to_draft_sections();
CREATE TRIGGER trg_subject_delete_guard BEFORE DELETE ON subjects
    FOR EACH ROW EXECUTE FUNCTION guard_subject_delete();

CREATE TRIGGER trg_sections_term BEFORE INSERT ON sections
    FOR EACH ROW EXECUTE FUNCTION set_section_term();
CREATE TRIGGER trg_sections_gates BEFORE UPDATE ON sections
    FOR EACH ROW EXECUTE FUNCTION enforce_section_gates();
CREATE TRIGGER trg_sections_created AFTER INSERT ON sections
    FOR EACH ROW EXECUTE FUNCTION after_section_created();
CREATE TRIGGER trg_sections_place_capacity AFTER UPDATE OF capacity ON sections
    FOR EACH ROW WHEN (NEW.capacity > OLD.capacity) EXECUTE FUNCTION trg_place_for_section();
CREATE TRIGGER trg_sections_approved_notify AFTER UPDATE OF schedule_status ON sections
    FOR EACH ROW WHEN (NEW.schedule_status = 'approved' AND OLD.schedule_status IS DISTINCT FROM 'approved')
    EXECUTE FUNCTION notify_schedule_approved();
CREATE TRIGGER trg_section_subjects_rules BEFORE INSERT OR UPDATE OR DELETE ON section_subjects
    FOR EACH ROW EXECUTE FUNCTION enforce_section_subject_rules();
CREATE TRIGGER trg_load_after_section_subject AFTER INSERT ON section_subjects
    FOR EACH ROW EXECUTE FUNCTION load_after_section_subject();

CREATE TRIGGER trg_student_sections_term BEFORE INSERT OR UPDATE OF section_id ON student_sections
    FOR EACH ROW EXECUTE FUNCTION set_enrollment_term();

CREATE TRIGGER trg_student_sections_x_leave_guard BEFORE INSERT ON student_sections
    FOR EACH ROW EXECUTE FUNCTION leave_guard_enrollment();
CREATE TRIGGER trg_load_after_enroll AFTER INSERT ON student_sections
    FOR EACH ROW EXECUTE FUNCTION load_after_enrollment();
CREATE TRIGGER trg_load_after_move AFTER UPDATE OF section_id ON student_sections
    FOR EACH ROW WHEN (OLD.section_id IS DISTINCT FROM NEW.section_id)
    EXECUTE FUNCTION load_after_enrollment();
CREATE TRIGGER trg_student_sections_returned AFTER INSERT ON student_sections
    FOR EACH ROW EXECUTE FUNCTION leave_after_enrollment();

CREATE TRIGGER trg_slips_gate BEFORE INSERT ON assessment_slips
    FOR EACH ROW EXECUTE FUNCTION enforce_slip_gate();
CREATE TRIGGER trg_slips_open_payment AFTER INSERT ON assessment_slips
    FOR EACH ROW EXECUTE FUNCTION open_payment_after_slip();
CREATE TRIGGER trg_payments_term BEFORE INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION set_payment_term();
CREATE TRIGGER trg_payments_gate BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION enforce_payment_gate();
CREATE TRIGGER trg_cors_gate BEFORE INSERT ON cors
    FOR EACH ROW EXECUTE FUNCTION enforce_cor_gate();

CREATE TRIGGER trg_enrollment_term_leaves AFTER UPDATE ON enrollment_term
    FOR EACH ROW
    WHEN (OLD.school_year IS DISTINCT FROM NEW.school_year OR OLD.semester IS DISTINCT FROM NEW.semester)
    EXECUTE FUNCTION after_term_changed_leaves();
CREATE TRIGGER trg_enrollment_term_open AFTER UPDATE ON enrollment_term
    FOR EACH ROW
    WHEN (OLD.school_year IS DISTINCT FROM NEW.school_year OR OLD.semester IS DISTINCT FROM NEW.semester)
    EXECUTE FUNCTION after_term_changed();

CREATE TRIGGER trg_audit_no_change BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_append_only();
CREATE TRIGGER trg_audit_no_truncate BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_append_only();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['grading_settings','grade_bands','grade_sheets','grades','grade_changes'] LOOP
    EXECUTE format('CREATE TRIGGER trg_grade_write_guard BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION refuse_direct_grade_write()', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['subject_prerequisites','student_credits'] LOOP
    EXECUTE format('CREATE TRIGGER trg_prerequisite_write_guard BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION refuse_direct_prerequisite_write()', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['term_closures','term_results'] LOOP
    EXECUTE format('CREATE TRIGGER trg_term_write_guard BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION refuse_direct_term_write()', t);
  END LOOP;
END $$;

CREATE TRIGGER trg_load_write_guard BEFORE INSERT OR UPDATE ON student_subjects
    FOR EACH ROW EXECUTE FUNCTION refuse_direct_load_write();
CREATE TRIGGER trg_leave_write_guard BEFORE INSERT OR UPDATE OR DELETE ON leaves
    FOR EACH ROW EXECUTE FUNCTION refuse_direct_leave_write();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'colleges','users','programs','program_payment_settings','admissions_connection_settings',
    'applicants','students','document_requirements','documents','visit_slots','visit_bookings',
    'subjects','rooms','sections','section_subjects','student_sections','student_subjects',
    'enrollment_term','assessment_slips','payments','cors','mass_reschedules','reschedule_requests',
    'grading_settings','grade_bands','grade_sheets','grades','grade_changes',
    'subject_prerequisites','student_credits','term_closures','term_results','leaves'
  ] LOOP
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION log_audit()', t);
  END LOOP;
END $$;

CREATE VIEW professor_class_lists AS
SELECT DISTINCT ss.section_id, sec.name AS section_name, sub.code AS subject_code, sub.title AS subject_title,
       st.student_number, u.full_name
FROM section_subjects ss
JOIN sections sec ON sec.id = ss.section_id
JOIN subjects sub ON sub.id = ss.subject_id
JOIN student_subjects ls ON ls.section_subject_id = ss.id
JOIN students st ON st.id = ls.student_id
JOIN applicants a ON a.id = st.applicant_id
JOIN users u ON u.id = a.user_id
WHERE ss.professor_id = current_actor_id();
GRANT SELECT ON professor_class_lists TO authenticated;

ALTER TABLE colleges                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                          ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_payment_settings       ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions_intake_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions_connection_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions_status_queue        ENABLE ROW LEVEL SECURITY;
ALTER TABLE applicants                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_number_counters        ENABLE ROW LEVEL SECURITY;
ALTER TABLE students                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_requirements          ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_slots                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_bookings                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                          ENABLE ROW LEVEL SECURITY;
ALTER TABLE sections                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE section_subjects               ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment_term                ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_sections               ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_subjects               ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_slips               ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cors                           ENABLE ROW LEVEL SECURITY;
ALTER TABLE mass_reschedules               ENABLE ROW LEVEL SECURITY;
ALTER TABLE reschedule_requests            ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE grading_settings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE grade_bands                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE grade_sheets                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE grades                         ENABLE ROW LEVEL SECURITY;
ALTER TABLE grade_changes                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE subject_prerequisites          ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_credits                ENABLE ROW LEVEL SECURITY;
ALTER TABLE term_closures                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE term_results                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE leaves                         ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'colleges','users','programs','program_payment_settings','admissions_intake_log',
    'admissions_connection_settings','applicants','students','document_requirements','documents',
    'visit_slots','visit_bookings','subjects','rooms','sections','section_subjects',
    'enrollment_term','student_sections','student_subjects','assessment_slips','payments','cors',
    'mass_reschedules','reschedule_requests','notifications',
    'grading_settings','grade_bands','grade_sheets','grades','grade_changes',
    'subject_prerequisites','student_credits','term_closures','term_results','leaves'
  ] LOOP
    EXECUTE format(
      'CREATE POLICY admin_all ON %I FOR ALL TO authenticated USING (app_role() = ''admin'') WITH CHECK (app_role() = ''admin'')', t);
  END LOOP;
END $$;
CREATE POLICY admin_read ON audit_log FOR SELECT TO authenticated USING (app_role() = 'admin');

CREATE POLICY read_all ON colleges FOR SELECT TO authenticated USING (true);
CREATE POLICY read_all ON programs FOR SELECT TO authenticated USING (true);
CREATE POLICY read_all ON document_requirements FOR SELECT TO authenticated USING (true);

CREATE POLICY users_self ON users FOR SELECT TO authenticated USING (id = current_actor_id());
CREATE POLICY users_registrar ON users FOR SELECT TO authenticated
    USING (app_role() = 'registrar' AND role IN ('applicant','student'));

CREATE POLICY users_registrar_professors ON users FOR SELECT TO authenticated
    USING (app_role() = 'registrar' AND role = 'professor');
CREATE POLICY users_finance ON users FOR SELECT TO authenticated
    USING (app_role() = 'finance' AND role = 'student');
CREATE POLICY users_college_staff ON users FOR SELECT TO authenticated
    USING (app_role() IN ('dean','college_secretary')
           AND (role = 'professor' OR (role IN ('applicant','student') AND user_in_my_college(id))));

CREATE POLICY pps_read ON program_payment_settings FOR SELECT TO authenticated
    USING (app_role() IN ('finance','registrar','dean'));
CREATE POLICY pps_finance_update ON program_payment_settings FOR UPDATE TO authenticated
    USING (app_role() = 'finance') WITH CHECK (app_role() = 'finance');

CREATE POLICY applicants_self ON applicants FOR SELECT TO authenticated USING (user_id = current_actor_id());
CREATE POLICY applicants_registrar ON applicants FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY applicants_college ON applicants FOR SELECT TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND program_in_my_college(program_id));

CREATE POLICY students_self ON students FOR SELECT TO authenticated USING (id = my_student_id());
CREATE POLICY students_registrar_finance ON students FOR SELECT TO authenticated
    USING (app_role() IN ('registrar','finance'));
CREATE POLICY students_college ON students FOR SELECT TO authenticated
    USING (app_role() IN ('dean','college_secretary') AND student_in_my_college(id));
CREATE POLICY students_registrar_insert ON students FOR INSERT TO authenticated
    WITH CHECK (app_role() = 'registrar');

CREATE POLICY documents_registrar ON documents FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');

CREATE POLICY slots_registrar ON visit_slots FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY slots_mine ON visit_slots FOR SELECT TO authenticated USING (id IN (SELECT my_visit_slot_ids()));
CREATE POLICY bookings_registrar ON visit_bookings FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY bookings_self ON visit_bookings FOR SELECT TO authenticated USING (applicant_id = my_applicant_id());

CREATE POLICY subjects_read ON subjects FOR SELECT TO authenticated
    USING (app_role() IN ('registrar','dean','college_secretary','professor'));
CREATE POLICY rooms_read ON rooms FOR SELECT TO authenticated
    USING (app_role() IN ('registrar','dean','college_secretary'));

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

CREATE POLICY slips_self ON assessment_slips FOR SELECT TO authenticated USING (student_id = my_student_id());
CREATE POLICY slips_registrar ON assessment_slips FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY payments_finance ON payments FOR ALL TO authenticated
    USING (app_role() = 'finance') WITH CHECK (app_role() = 'finance');
CREATE POLICY payments_registrar_read ON payments FOR SELECT TO authenticated USING (app_role() = 'registrar');
CREATE POLICY cors_self ON cors FOR SELECT TO authenticated USING (student_id = my_student_id());
CREATE POLICY cors_registrar ON cors FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');

CREATE POLICY mass_reschedules_registrar ON mass_reschedules FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY requests_registrar ON reschedule_requests FOR ALL TO authenticated
    USING (app_role() = 'registrar') WITH CHECK (app_role() = 'registrar');
CREATE POLICY requests_self_read ON reschedule_requests FOR SELECT TO authenticated USING (requested_by = current_actor_id());

CREATE POLICY requests_applicant_student_insert ON reschedule_requests FOR INSERT TO authenticated
    WITH CHECK (
      app_role() IN ('applicant','student')
      AND requested_by = current_actor_id()
      AND booking_id IN (SELECT vb.id FROM visit_bookings vb WHERE vb.applicant_id = my_applicant_id())
    );

CREATE POLICY notifications_self ON notifications FOR SELECT TO authenticated USING (user_id = current_actor_id());

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'assign_visit_slot_core(uuid,uuid,text)',
    'can_see_sheet(uuid,uuid)',
    'copy_section_load(uuid,uuid)',
    'generate_student_number()',
    'grading_scale_ready()',
    'has_enrollment_after(uuid,text,text)',
    'in_section_subject(uuid,uuid,uuid)',
    'leave_covers_term(text,text,text,text,text,text)',
    'leave_json(leaves)',
    'leave_return_term(text,text,integer)',
    'leave_terms_used(uuid)',
    'next_regular_term(text,text)',
    'open_term(text,text)',
    'place_student_in_section(uuid)',
    'place_waiting_students(uuid)',
    'previous_regular_term(text,text)',
    'resolve_grade(text)',
    'run_leave_catch_up()',
    'student_blocking_prerequisites(uuid,uuid)',
    'student_enrollment(uuid)',
    'student_has_passed(uuid,uuid)',
    'student_load_ready(uuid)',
    'student_schedule_json(uuid)',
    'term_missing_sheets()',
    'term_order(text,text)',
    'term_text(text,text)',
    'withdraw_enrollment_core(uuid,text)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
  END LOOP;

  FOREACH f IN ARRAY ARRAY[
    'add_subject_to_load(uuid,uuid,uuid)',
    'amend_schedule(uuid,uuid,uuid,smallint,time without time zone,time without time zone,text)',
    'approve_credit(uuid)',
    'approve_grade_change(uuid)',
    'approve_grades(uuid,uuid)',
    'assessment_slip(uuid)',
    'assign_unassigned_visits(uuid)',
    'assign_visit_slot(uuid,uuid,text)',
    'certificate_of_registration(uuid)',
    'close_term()',
    'completed_students()',
    'cor_ready_students()',
    'correct_student_details(uuid,text,text,text)',
    'credit_overview(uuid)',
    'credits_pending()',
    'current_term()',
    'decide_leave(uuid,boolean,text)',
    'decide_reschedule(uuid,boolean,uuid,text)',
    'document_checklist_text(text)',
    'grade_changes_list()',
    'grade_sections()',
    'grade_sheet(uuid,uuid)',
    'grading_scale()',
    'issue_all_ready_cors()',
    'issue_all_ready_slips()',
    'issue_assessment_slip(uuid)',
    'issue_cor(uuid)',
    'lapse_incomplete_grades()',
    'leave_catch_up()',
    'leave_overview(uuid)',
    'leave_requests()',
    'mark_documents_received(uuid)',
    'mass_reschedule(date,uuid,text,text)',
    'move_student_section(uuid,uuid,text)',
    'my_leave()',
    'my_needs_advising()',
    'my_open_late_items()',
    'my_payment_status()',
    'my_readmission()',
    'my_schedule_changed()',
    'next_open_slot(uuid,date,text)',
    'payment_queue(text)',
    'prerequisite_programs()',
    'prerequisites_list(uuid)',
    'propose_grade_change(uuid,text,text)',
    'record_credit(uuid,uuid,text)',
    'record_leave(uuid,text,text,integer,text)',
    'record_payment(uuid,numeric,numeric,text)',
    'reject_credit(uuid,text)',
    'reject_grade_change(uuid,text)',
    'reject_schedule(uuid,text)',
    'remove_subject_from_load(uuid,uuid)',
    'request_reschedule(text)',
    'return_grades(uuid,uuid,text)',
    'review_students()',
    'save_grade_scale(jsonb,integer)',
    'save_grades(uuid,uuid,jsonb)',
    'save_prerequisites(uuid,uuid[])',
    'sign_grade_change(uuid)',
    'slip_ready_students()',
    'student_load(uuid)',
    'students_on_leave()',
    'subject_eligibility(uuid,uuid)',
    'submit_grades(uuid,uuid)',
    'term_close_status()',
    'withdraw_applicant(uuid,text)',
    'withdraw_my_enrollment(text)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;

  FOREACH f IN ARRAY ARRAY[
    'admissions_status_due(integer)',
    'auto_assign_visit(uuid)',
    'record_admissions_status(uuid,text,boolean,text,boolean)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;

INSERT INTO colleges (code, name) VALUES
    ('CCS', 'College of Computer Studies'),
    ('CON', 'College of Nursing'),
    ('CBA', 'College of Business and Accountancy'),
    ('COE', 'College of Education'),
    ('CAS', 'College of Arts and Sciences'),
    ('CEN', 'College of Engineering'),
    ('HM',  'College of Hospitality Management');

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
JOIN colleges c ON c.code = v.college_code;

INSERT INTO document_requirements (doc_type, label, applies_to, required, sort_order) VALUES
    ('endorsement_slip',  'Endorsement Slip signed by the Admissions Officer',                          ARRAY['new','transferee','foreign'], true,  10),
    ('psa_birth_cert',    'PSA birth certificate, original and photocopy',                              ARRAY['new','transferee','foreign'], true,  20),
    ('photo_2x2',         'One recent 2x2 photo, white background',                                     ARRAY['new','transferee','foreign'], true,  30),
    ('student_info_form', 'Printed Student Information Form',                                           ARRAY['new','transferee','foreign'], true,  40),
    ('valid_ids',         'Two valid IDs, original and photocopy, one showing current address',         ARRAY['new','transferee'],           true,  50),
    ('form_138',          'Form 138 (report card)',                                                     ARRAY['new'],                        true,  60),
    ('tor',               'TOR marked "Copy for PLP"',                                                  ARRAY['transferee','foreign'],       true,  70),
    ('passport',          'Passport',                                                                   ARRAY['foreign'],                    true,  80),
    ('visa_permit',       'Visa or Study Permit',                                                       ARRAY['foreign'],                    true,  90),
    ('acr',               'Alien Certificate of Registration',                                          ARRAY['foreign'],                    true,  100),
    ('form_137',          'Original SHS Form 137 marked "Copy for Pamantasan ng Lungsod ng Pasig"',     ARRAY['new'],                        false, 110),
    ('other',             'Other document (note required)',                                             ARRAY['new','transferee','foreign'], false, 120);
