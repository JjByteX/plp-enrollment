-- ============================================================
-- supabase/seeders/07_bsit_section_2a.sql
-- Section BSIT 2A (Year 2, 1st semester) with the weekly schedule from the
-- sample COR. Run after 02 (faculty), 03 (rooms) and 05 (subjects).
-- Days: 1 Monday ... 7 Sunday (T = 2, W = 3, TH = 4, F = 5).
-- The section stays in 'draft' (see 06_bsit_section_1a.sql). Safe to re-run.
-- ============================================================
INSERT INTO sections (program_id, name, year_level, capacity)
SELECT p.id, '2A', 2, 40
FROM programs p WHERE p.code = 'BSIT'
ON CONFLICT (program_id, year_level, name) DO NOTHING;

UPDATE section_subjects ss
   SET professor_id = (SELECT u.id FROM users u WHERE u.email = v.prof_email),
       room_id      = (SELECT r.id FROM rooms r WHERE r.name = v.room),
       day_of_week  = v.day,
       start_time   = v.start_time::time,
       end_time     = v.end_time::time
  FROM (VALUES
    -- code,       meeting,      professor,                 room,    day, start,   end
    ('COMP 104',  'lecture',    'prof.ccs1@plp.edu.ph',    'RM702', 4,  '08:00', '10:00'),
    ('COMP 104',  'laboratory', 'prof.ccs1@plp.edu.ph',    'CLAB2', 2,  '11:00', '14:00'),
    ('COMP 105',  'lecture',    'prof.ccs2@plp.edu.ph',    'CLAB4', 4,  '11:00', '14:00'),
    ('COMP 105',  'laboratory', 'prof.ccs2@plp.edu.ph',    'RM606', 5,  '08:00', '10:00'),
    ('GE 008',    'lecture',    'prof.cas.ge@plp.edu.ph',  'RM607', 3,  '08:00', '11:00'),
    ('GEE 002',   'lecture',    'prof.cas.ge@plp.edu.ph',  'RM705', 2,  '14:30', '17:30'),
    ('IT 102',    'lecture',    'prof.ccs3@plp.edu.ph',    'RM607', 5,  '10:30', '13:30'),
    ('IT 201',    'lecture',    'prof.ccs3@plp.edu.ph',    'RM703', 3,  '12:00', '14:00'),
    ('IT 201',    'laboratory', 'prof.ccs3@plp.edu.ph',    'CLAB3', 4,  '14:30', '17:30'),
    ('IT 202',    'lecture',    'prof.ccs4@plp.edu.ph',    'CLAB4', 3,  '14:30', '17:30'),
    ('IT 202',    'laboratory', 'prof.ccs4@plp.edu.ph',    'RM606', 5,  '14:30', '16:30'),
    ('PE 103',    'lecture',    'prof.cas.pe@plp.edu.ph',  'GYM-A', 2,  '08:00', '10:00')
  ) AS v(code, meeting, prof_email, room, day, start_time, end_time)
  JOIN subjects sub ON sub.code = v.code
  JOIN programs p   ON p.id = sub.program_id AND p.code = 'BSIT'
  JOIN sections sec ON sec.program_id = p.id AND sec.year_level = 2 AND sec.name = '2A'
 WHERE ss.section_id = sec.id
   AND ss.subject_id = sub.id
   AND ss.meeting = v.meeting
   AND sec.schedule_status = 'draft';
