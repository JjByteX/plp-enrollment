-- ============================================================
-- supabase/seeders/optional/bsit_year1_2nd_sem.sql
-- BSIT Year 1, 2nd semester (from the sample COR). NOT loaded automatically:
-- the seeder runner only reads seeders/*.sql, not this folder.
--
-- WHY OPTIONAL: subjects has no semester column, and section 1A takes every
-- Year 1 subject. Loading this on top of 05_bsit_subjects.sql would put both
-- semesters (43 units) in one section. Use it for a database that is
-- running the 2nd semester, in place of the Year 1 part of 05 (that is,
-- seed 05 with the Year 1 rows removed), or after adding a semester to
-- subjects.
--
-- Run after 02, 03 and 05. GEE 302 meets Tuesday and Thursday 9:00-10:30 on
-- the COR, but a schedule row holds one day, so only Tuesday is seeded.
-- Days: 1 Monday ... 7 Sunday. Safe to re-run.
-- ============================================================
INSERT INTO subjects (program_id, code, title, units, year_level, has_laboratory)
SELECT p.id, v.code, v.title, v.units, 1, v.has_lab
FROM (VALUES
    ('COMP 103',   'Intermediate Programming (Java)',                                  3.0, true),
    ('GE 001',     'Understanding the Self',                                           3.0, false),
    ('GE 005',     'Purposive Communication',                                          3.0, false),
    ('GE 007',     'Science, Technology and Society',                                  3.0, false),
    ('GEE 302',    'GE Elective: Environmental Science',                               3.0, false),
    ('IT 101',     'Discrete Mathematics',                                             3.0, false),
    ('NSTP 102-C', 'National Service Training Program (Civic Welfare Training Service)', 3.0, false),
    ('PE 102',     'Physical Activities Towards Health and Fitness 2 (PATHfit 2)',     2.0, false)
) AS v(code, title, units, has_lab)
CROSS JOIN programs p
WHERE p.code = 'BSIT'
ON CONFLICT (program_id, code) DO UPDATE
   SET title = EXCLUDED.title, units = EXCLUDED.units,
       year_level = EXCLUDED.year_level, has_laboratory = EXCLUDED.has_laboratory;

INSERT INTO sections (program_id, name, year_level, capacity)
SELECT p.id, '1A', 1, 40 FROM programs p WHERE p.code = 'BSIT'
ON CONFLICT (program_id, year_level, name) DO NOTHING;

UPDATE section_subjects ss
   SET professor_id = (SELECT u.id FROM users u WHERE u.email = v.prof_email),
       room_id      = (SELECT r.id FROM rooms r WHERE r.name = v.room),
       day_of_week  = v.day,
       start_time   = v.start_time::time,
       end_time     = v.end_time::time
  FROM (VALUES
    ('COMP 103',   'lecture',    'prof.ccs6@plp.edu.ph',    'RM709', 5,  '08:00', '10:00'),
    ('COMP 103',   'laboratory', 'prof.ccs6@plp.edu.ph',    'CLAB2', 5,  '10:30', '13:30'),
    ('GE 001',     'lecture',    'prof.cas.ge2@plp.edu.ph', 'RM705', 4,  '17:00', '20:00'),
    ('GE 005',     'lecture',    'prof.cas.ge2@plp.edu.ph', 'RM713', 3,  '16:00', '19:00'),
    ('GE 007',     'lecture',    'prof.cas.ge2@plp.edu.ph', 'RM705', 3,  '07:30', '10:30'),
    ('GEE 302',    'lecture',    'prof.cas.ge2@plp.edu.ph', 'RM713', 2,  '09:00', '10:30'),
    ('IT 101',     'lecture',    'prof.ccs3@plp.edu.ph',    'RM713', 2,  '14:30', '17:30'),
    ('NSTP 102-C', 'lecture',    'prof.nstp@plp.edu.ph',    'RM705', 5,  '14:00', '17:00'),
    ('PE 102',     'lecture',    'prof.cas.pe@plp.edu.ph',  'RM709', 4,  '14:30', '16:30')
  ) AS v(code, meeting, prof_email, room, day, start_time, end_time)
  JOIN subjects sub ON sub.code = v.code
  JOIN programs p   ON p.id = sub.program_id AND p.code = 'BSIT'
  JOIN sections sec ON sec.program_id = p.id AND sec.year_level = 1 AND sec.name = '1A'
 WHERE ss.section_id = sec.id
   AND ss.subject_id = sub.id
   AND ss.meeting = v.meeting
   AND sec.schedule_status = 'draft';
