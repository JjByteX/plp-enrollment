-- ============================================================
-- supabase/seeders/03_rooms.sql
-- Rooms used by the sample schedules (from the sample CORs). Computer labs
-- belong to CCS; classrooms and the gym are shared by every college
-- (college_id NULL). Safe to re-run.
-- ============================================================
INSERT INTO rooms (name, college_id)
SELECT v.name, (SELECT c.id FROM colleges c WHERE c.code = v.college_code)
FROM (VALUES
    ('RM606',  NULL), ('RM607',  NULL), ('RM702',  NULL), ('RM703',  NULL),
    ('RM705',  NULL), ('RM709',  NULL), ('RM712',  NULL), ('RM713',  NULL),
    ('RM925',  NULL), ('GYM-A',  NULL),
    ('CLAB1',  'CCS'), ('CLAB2',  'CCS'), ('CLAB3',  'CCS'), ('CLAB4',  'CCS')
) AS v(name, college_code)
ON CONFLICT (name) DO NOTHING;
