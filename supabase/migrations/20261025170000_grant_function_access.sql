-- Forward-only follow-up. Lets the signed-in role (authenticated) call the
-- app-facing functions.
--
-- Earlier migrations revoked EXECUTE on these functions from PUBLIC and anon
-- but never granted it to authenticated. Some Supabase projects no longer
-- grant function access to the API roles automatically, so every call from
-- the app failed (for example "The documents could not be marked received").
-- Same reason as 20261025130000_grant_table_access.sql, which covers tables.
--
-- Every function below checks the caller's role itself, so granting EXECUTE
-- does not let the wrong person act. Internal functions (generate_student_number,
-- place_student_in_section, place_waiting_students, assign_visit_slot_core,
-- auto_assign_visit, record_admissions_status, admissions_status_due) are
-- deliberately NOT granted here.
--
-- Looks each function up by name, so it does not depend on exact argument
-- lists, and it is safe to run twice.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'mark_documents_received', 'document_checklist_text', 'assign_visit_slot',
        'assign_unassigned_visits', 'next_open_slot', 'assessment_slip',
        'issue_assessment_slip', 'issue_all_ready_slips', 'certificate_of_registration',
        'issue_cor', 'issue_all_ready_cors', 'decide_reschedule', 'mass_reschedule',
        'request_reschedule', 'move_student_section', 'reject_schedule',
        'payment_queue', 'record_payment', 'my_payment_status', 'my_open_late_items'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;
