-- Documents that Admissions staff already approved (as scans), sent with the
-- intake call. Information only: the Registrar still receives and ticks the
-- originals herself, so nothing here ever marks a document received.
-- Values are document_requirements.doc_type slugs. Safe to run twice.
ALTER TABLE applicants
    ADD COLUMN IF NOT EXISTS admissions_verified_docs text[] NOT NULL DEFAULT '{}';
COMMENT ON COLUMN applicants.admissions_verified_docs IS 'doc_type slugs Admissions approved before the handoff. Shown to the Registrar as "Verified in Admissions"; never ticks a document.';
