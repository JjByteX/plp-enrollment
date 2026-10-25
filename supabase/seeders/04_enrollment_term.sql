-- ============================================================
-- supabase/seeders/04_enrollment_term.sql
-- The term stamped on every COR. One row. Admin can change it in the app.
-- Does nothing if a term is already set.
-- ============================================================
INSERT INTO enrollment_term (school_year, semester)
VALUES ('2026-2027', '1st')
ON CONFLICT (id) DO NOTHING;
