-- ============================================================
-- supabase/seeders/09_bsit_prospectus.sql
-- BSIT prospectus (revised curriculum AY 2022-2023, PLP_BSIT_Course_Prospectus.pdf):
-- the subjects not already in 05, and every prerequisite.
-- Run after 05. Safe to re-run: existing subjects are left as they are.
--
-- Subjects already in 05 (1st semester Year 1 and Year 2) are not repeated.
-- Year 1 2nd semester subjects are added here with their own semester, so a
-- section only takes the subjects of its term. Summer subjects are tagged 'summer'.
-- has_laboratory = true where the prospectus shows lab hours.
--
-- NOT SEEDED: "3rd Yr Standing" (IT 303, IT 110). It is a year-level rule, not a
-- subject, and subject_prerequisites can only hold subjects.
-- The GE elective choices (Environmental Science, Gender and Society ...) have no
-- course codes in the prospectus; add them in Admin > Content when they are scheduled.
-- ============================================================
INSERT INTO subjects (program_id, code, title, units, year_level, has_laboratory, semester)
SELECT p.id, v.code, v.title, v.units, v.year_level, v.has_lab, v.semester
FROM (VALUES
    -- Year 1, 2nd semester (23 units)
    ('COMP 103',   'Intermediate Programming (Java)',                                  3.0, 1, true,  '2nd'),
    ('GE 001',     'Understanding the Self',                                           3.0, 1, false, '2nd'),
    ('GE 005',     'Purposive Communication',                                          3.0, 1, false, '2nd'),
    ('GE 007',     'Science, Technology and Society',                                  3.0, 1, false, '2nd'),
    ('GEE 001',    'GE Elective 1',                                                    3.0, 1, false, '2nd'),
    ('IT 101',     'Discrete Mathematics',                                             3.0, 1, false, '2nd'),
    ('NSTP 102-C', 'National Service Training Program (Civic Welfare Training Service)', 3.0, 1, false, '2nd'),
    ('PE 102',     'Self-Defense',                                                     2.0, 1, false, '2nd'),
    -- Year 2, 2nd semester (23 units)
    ('COMP 106',   'Applications Development and Emerging Technologies',               3.0, 2, true,  '2nd'),
    ('GE 002',     'Readings in Philippine History with Indigenous Peoples'' Education', 3.0, 2, false, '2nd'),
    ('GEE 003',    'GE Elective 3',                                                    3.0, 2, false, '2nd'),
    ('IT 103',     'Advanced Database Systems',                                        3.0, 2, true,  '2nd'),
    ('IT 104',     'Integrative Programming and Technologies I',                       3.0, 2, true,  '2nd'),
    ('IT 105',     'Networking I',                                                     3.0, 2, true,  '2nd'),
    ('IT 301',     'Web Programming',                                                  3.0, 2, true,  '2nd'),
    ('PE 104',     'Team Games and Sports',                                            2.0, 2, false, '2nd'),
    -- Year 3, 1st semester (21 units)
    ('GE 009',     'Rizal''s Life and Works',                                          3.0, 3, false, '1st'),
    ('IT 106',     'Systems Integration and Architecture 1',                           3.0, 3, true,  '1st'),
    ('IT 107',     'Networking II',                                                    3.0, 3, true,  '1st'),
    ('IT 302',     'Software Engineering',                                             3.0, 3, true,  '1st'),
    ('IT 303',     'Technopreneurship',                                                3.0, 3, false, '1st'),
    ('IT 304',     'IT Professional Ethics',                                           3.0, 3, false, '1st'),
    ('IT 305',     'Web Development',                                                  3.0, 3, true,  '1st'),
    -- Year 3, 2nd semester (15 units)
    ('IT 108',     'Information Assurance and Security I',                             3.0, 3, true,  '2nd'),
    ('IT 109',     'Introduction to Human Computer Interaction',                       3.0, 3, true,  '2nd'),
    ('IT 110',     'Social and Professional Issues',                                   3.0, 3, false, '2nd'),
    ('IT 203',     'IT Elective: Integrative Programming and Technologies II',         3.0, 3, true,  '2nd'),
    ('IT 306',     'Multimedia and Technologies',                                      3.0, 3, true,  '2nd'),
    -- Year 3, summer (6 units)
    ('IT 111',     'IT Capstone Project I',                                            3.0, 3, false, 'summer'),
    ('IT 112',     'Information Assurance and Security II',                            3.0, 3, true,  'summer'),
    -- Year 4, 1st semester (9 units)
    ('IT 113',     'System Administration and Maintenance',                            3.0, 4, true,  '1st'),
    ('IT 114',     'IT Capstone Project II',                                           3.0, 4, false, '1st'),
    ('IT 204',     'IT Elective: Systems Integration and Architecture II',             3.0, 4, true,  '1st'),
    -- Year 4, 2nd semester (6 units)
    ('IT 115',     'On-the-Job Training (486 hours)',                                  6.0, 4, false, '2nd')
) AS v(code, title, units, year_level, has_lab, semester)
CROSS JOIN programs p
WHERE p.code = 'BSIT'
ON CONFLICT (program_id, code) DO NOTHING;

-- Prerequisites, exactly as listed in the prospectus.
INSERT INTO subject_prerequisites (subject_id, prerequisite_id)
SELECT s.id, r.id
FROM (VALUES
    ('COMP 103', 'COMP 102'),
    ('COMP 104', 'COMP 103'),
    ('COMP 105', 'COMP 103'),
    ('IT 102',   'IT 101'),
    ('IT 201',   'COMP 103'),
    ('IT 202',   'COMP 103'),
    ('IT 103',   'COMP 105'),
    ('IT 104',   'IT 201'),
    ('IT 104',   'IT 202'),
    ('IT 105',   'IT 201'),
    ('IT 301',   'COMP 103'),
    ('COMP 106', 'COMP 105'),
    ('IT 106',   'IT 104'),
    ('IT 107',   'IT 105'),
    ('IT 302',   'COMP 105'),
    ('IT 305',   'IT 301'),
    ('IT 108',   'IT 106'),
    ('IT 109',   'COMP 102'),
    ('IT 203',   'IT 104'),
    ('IT 111',   'IT 108'),
    ('IT 111',   'COMP 106'),
    ('IT 111',   'IT 302'),
    ('IT 112',   'IT 108'),
    ('IT 112',   'COMP 106'),
    ('IT 113',   'IT 112'),
    ('IT 114',   'IT 111'),
    ('IT 204',   'IT 106'),
    ('IT 115',   'IT 108'),
    ('IT 115',   'COMP 106')
) AS v(code, prereq)
CROSS JOIN programs p
JOIN subjects s ON s.program_id = p.id AND s.code = v.code
JOIN subjects r ON r.program_id = p.id AND r.code = v.prereq
WHERE p.code = 'BSIT'
ON CONFLICT (subject_id, prerequisite_id) DO NOTHING;
