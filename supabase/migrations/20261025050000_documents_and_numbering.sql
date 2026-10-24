-- Forward-only follow-up (never edit a merged migration).
-- Step 7, Documents and student numbering. See docs/step-7-documents-and-numbering-plan.md.
--
-- 1. document_requirements: the catalog of what each admission type brings.
-- 2. documents: reshaped so one row means "this document was received".
-- 3. enforce_documents_open: required items lock once the applicant is a student.
-- 4. document_checklist_text(type): the checklist as text, for notifications and the card.
-- 5. mark_documents_received(applicant): the one way an Applicant becomes a Student.
-- 6. assign_visit_slot replaced: "what to bring" now comes from the checklist (decision C).
-- 7. Who may call the functions.
--
-- The student number and promotion triggers from the earlier migrations are
-- used as they are. generate_student_number() and promote_applicant_to_student()
-- are not touched. Nothing here sends email: the notification is written with
-- email_status = 'pending' for the sender that comes later.

-- ============================================================
-- 1. Catalog of required documents
--    Seeded here. There is no editor until step 15, so a change is a new
--    migration. Admin is the only role that can write it.
-- ============================================================
CREATE TABLE IF NOT EXISTS document_requirements (
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

ALTER TABLE document_requirements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_all ON document_requirements;
CREATE POLICY admin_all ON document_requirements FOR ALL TO authenticated
    USING (app_role() = 'admin') WITH CHECK (app_role() = 'admin');

-- Labels are not sensitive and the applicant card shows them.
DROP POLICY IF EXISTS read_all ON document_requirements;
CREATE POLICY read_all ON document_requirements FOR SELECT TO authenticated USING (true);

DROP TRIGGER IF EXISTS trg_audit ON document_requirements;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON document_requirements
    FOR EACH ROW EXECUTE FUNCTION log_audit();

-- Draft list for the Registrar to confirm. Sources are in the step 7 plan.
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
    ('other',             'Other document (note required)',                                             ARRAY['new','transferee','foreign'], false, 120)
ON CONFLICT (doc_type) DO NOTHING;

-- ============================================================
-- 2. Reshape documents
--    Before: a row per uploaded file (storage_path, uploaded_by, four doc
--    types). Nothing ever wrote to it. Now: a row per received document,
--    no file (decision A). Missing row = not received.
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM documents) THEN
    RAISE EXCEPTION 'documents already has rows. This migration assumes the table is empty (nothing wrote to it before step 7). Check the rows, then decide how to carry them over';
  END IF;
END $$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.contype = 'c'
      AND c.conrelid = 'public.documents'::regclass
      AND pg_get_constraintdef(c.oid) LIKE '%doc_type%'
  LOOP
    EXECUTE format('ALTER TABLE documents DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE documents ALTER COLUMN storage_path DROP NOT NULL;
ALTER TABLE documents ALTER COLUMN uploaded_by  DROP NOT NULL;
COMMENT ON COLUMN documents.storage_path IS 'Unused. Admissions holds the approved scans; Enrollment keeps a tick only (step 7 decision A).';
COMMENT ON COLUMN documents.uploaded_by  IS 'Unused, see storage_path.';

ALTER TABLE documents ADD COLUMN IF NOT EXISTS received_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE documents ADD COLUMN IF NOT EXISTS received_by uuid NOT NULL REFERENCES users (id);
ALTER TABLE documents ADD COLUMN IF NOT EXISTS note varchar(200) NULL;

ALTER TABLE documents
    ADD CONSTRAINT documents_doc_type_fkey FOREIGN KEY (doc_type) REFERENCES document_requirements (doc_type);
ALTER TABLE documents
    ADD CONSTRAINT documents_applicant_doc_type_key UNIQUE (applicant_id, doc_type);
ALTER TABLE documents
    ADD CONSTRAINT documents_other_needs_note CHECK (doc_type <> 'other' OR nullif(trim(note), '') IS NOT NULL);

-- The unique key above already starts with applicant_id.
DROP INDEX IF EXISTS idx_documents_applicant;

-- ============================================================
-- 3. Guard on documents
--    - Insert stamps who and when (nobody types received_by).
--    - A document must be active and apply to the applicant's type.
--    - The applicant and the type of a row never change.
--    - Once the applicant is a student, required items are locked.
--      Late items stay tickable. Admin is not exempt.
-- ============================================================
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
DROP TRIGGER IF EXISTS trg_documents_open ON documents;
CREATE TRIGGER trg_documents_open BEFORE INSERT OR UPDATE OR DELETE ON documents
    FOR EACH ROW EXECUTE FUNCTION enforce_documents_open();

-- ============================================================
-- 4. The checklist for one admission type, as text
--    Required items first, late items after, numbered. "Other" is left
--    out: it is the Registrar's own tick, not something to bring.
--    Returns null when the type has no active items.
-- ============================================================
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

-- ============================================================
-- 5. Mark documents received
--    One transaction: lock the applicant, check the required items,
--    insert the students row (the existing triggers assign the YY-NNNNN
--    number, stamp who and when, and flip the role), mark a booked visit
--    attended, write the notification. Any error rolls all of it back.
--    The missing-documents check runs before the insert, so a refused
--    promotion never consumes a student number.
--    There is no override for missing required documents (decision B).
-- ============================================================
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

  -- Two Registrars on the same applicant queue here; the second one then
  -- finds the students row and stops.
  SELECT * INTO v_app FROM applicants WHERE id = p_applicant FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
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

  -- Only a booking that is still "booked". An attended or no_show booking stays as it is.
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

-- ============================================================
-- 6. assign_visit_slot, replaced (decision C)
--    Same arguments, same checks, same notification kinds. The only
--    change: what_to_bring is the checklist for the applicant's
--    admission type, followed by the slot's own notes when there are any.
--    Written from 20261025040000_visit_scheduling.sql.
-- ============================================================
CREATE OR REPLACE FUNCTION assign_visit_slot(p_applicant uuid, p_slot uuid, p_reason text DEFAULT NULL)
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
  IF app_role() IS NULL OR app_role() NOT IN ('registrar','admin') THEN
    RAISE EXCEPTION 'Only the Registrar or Admin can assign visits';
  END IF;

  SELECT user_id, admission_type INTO v_user, v_type FROM applicants WHERE id = p_applicant;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Applicant not found';
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

-- ============================================================
-- 7. Who may call them. The functions also check the role themselves.
--    The checklist text only reads labels, so any signed-in user may call it.
-- ============================================================
REVOKE EXECUTE ON FUNCTION mark_documents_received(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION document_checklist_text(text) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION mark_documents_received(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION document_checklist_text(text) FROM anon;
  END IF;
END $$;
