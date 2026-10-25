-- ============================================================
-- supabase/seeders/06_bsit_section_1a.sql
-- Section BSIT 1A (Year 1, 1st semester) with the weekly schedule from the
-- sample COR. Run after 02 (faculty), 03 (rooms) and 05 (subjects).
--
-- Creating the section fills one row per subject (and per laboratory) by
-- itself, and places any student already waiting for a Year 1 BSIT seat.
-- This file then fills in professor, room, day and time.
-- Days: 1 Monday ... 7 Sunday (T = 2, W = 3, TH = 4, F = 5).
--
-- The section stays in 'draft'. The College Secretary submits it, the Dean
-- signs it, and it is approved in the app, the same as in real use.
-- Safe to re-run.
-- ============================================================
INSERT INTO sections (program_id, name, year_level, capacity)
SELECT p.id, '1A', 1, 40
FROM programs p WHERE p.code = 'BSIT'
ON CONFLICT (program_id, year_level, name) DO NOTHING;

UPDATE section_subjects ss
   SET professor_id = (SELECT u.id FROM users u WHERE u.email = v.prof_email),
       room_id      = (SELECT r.id FROM rooms r WHERE r.name = v.room),
       day_of_week  = v.day,
       start_time   = v.start_time::time,
       end_time     = v.end_time::time
  FROM (VALUES
    -- code,        meeting,      professor,                 room,    day, start,   end
    ('COMP 101',   'lecture',    'prof.ccs5@plp.edu.ph',    'RM712', 3,  '09:30', '11:30'),
    ('COMP 101',   'laboratory', 'prof.ccs5@plp.edu.ph',    'CLAB2', 2,  '07:30', '10:30'),
    ('COMP 102',   'lecture',    'prof.ccs6@plp.edu.ph',    'RM712', 4,  '12:00', '14:00'),
    ('COMP 102',   'laboratory', 'prof.ccs6@plp.edu.ph',    'CLAB1', 5,  '14:30', '17:30'),
    ('GE 003',     'lecture',    'prof.cas.ge@plp.edu.ph',  'RM712', 3,  '15:30', '18:30'),
    ('GE 004',     'lecture',    'prof.cas.ge2@plp.edu.ph', 'RM712', 5,  '11:00', '14:00'),
    ('GE 006',     'lecture',    'prof.cas.ge@plp.edu.ph',  'RM712', 3,  '12:00', '15:00'),
    ('NSTP 101-C', 'lecture',    'prof.nstp@plp.edu.ph',    'RM712', 4,  '08:00', '11:00'),
    ('PE 101',     'lecture',    'prof.cas.pe@plp.edu.ph',  'RM925', 5,  '18:00', '20:00')
  ) AS v(code, meeting, prof_email, room, day, start_time, end_time)
  JOIN subjects sub ON sub.code = v.code
  JOIN programs p   ON p.id = sub.program_id AND p.code = 'BSIT'
  JOIN sections sec ON sec.program_id = p.id AND sec.year_level = 1 AND sec.name = '1A'
 WHERE ss.section_id = sec.id
   AND ss.subject_id = sub.id
   AND ss.meeting = v.meeting
   AND sec.schedule_status = 'draft';
