-- ============================================================
-- supabase/seeders/05_bsit_subjects.sql
-- BS Information Technology, 1st semester, Year 1 and Year 2 (from the sample
-- CORs). Only subject codes, titles and units are taken from them.
--
-- has_laboratory = true means the section also gets a unit-less laboratory
-- meeting row (the "COMP 101 Lab" line on a COR).
--
-- subjects has no semester column and a new section takes every subject of
-- its year level, so only ONE semester per year level is loaded here (the
-- current term, 1st). The 1st year 2nd semester subjects are in
-- optional/bsit_year1_2nd_sem.sql. Safe to re-run.
-- ============================================================
INSERT INTO subjects (program_id, code, title, units, year_level, has_laboratory)
SELECT p.id, v.code, v.title, v.units, v.year_level, v.has_lab
FROM (VALUES
    -- Year 1, 1st semester (20 units)
    ('COMP 101',  'Introduction to Computing',                                        3.0, 1, true),
    ('COMP 102',  'Fundamentals of Programming (C++)',                                3.0, 1, true),
    ('GE 003',    'The Contemporary World with Peace Education',                      3.0, 1, false),
    ('GE 004',    'Mathematics in the Modern World',                                  3.0, 1, false),
    ('GE 006',    'Art Appreciation',                                                 3.0, 1, false),
    ('NSTP 101-C','National Service Training Program (Civic Welfare Training Service)', 3.0, 1, false),
    ('PE 101',    'Physical Activities Towards Health and Fitness 1 (PATHfit 1)',     2.0, 1, false),
    -- Year 2, 1st semester (23 units)
    ('COMP 104',  'Data Structures and Algorithms',                                   3.0, 2, true),
    ('COMP 105',  'Information Management',                                           3.0, 2, true),
    ('GE 008',    'Ethics',                                                           3.0, 2, false),
    ('GEE 002',   'GE Elective 2: Living in the IT Era',                              3.0, 2, false),
    ('IT 102',    'Quantitative Methods',                                             3.0, 2, false),
    ('IT 201',    'IT Elective: Platform Technologies',                               3.0, 2, true),
    ('IT 202',    'IT Elective: Object-Oriented Programming (VB.Net)',                3.0, 2, true),
    ('PE 103',    'Physical Activities Towards Health and Fitness 3 (PATHfit 3)',     2.0, 2, false)
) AS v(code, title, units, year_level, has_lab)
CROSS JOIN programs p
WHERE p.code = 'BSIT'
ON CONFLICT (program_id, code) DO UPDATE
   SET title = EXCLUDED.title,
       units = EXCLUDED.units,
       year_level = EXCLUDED.year_level,
       has_laboratory = EXCLUDED.has_laboratory;
