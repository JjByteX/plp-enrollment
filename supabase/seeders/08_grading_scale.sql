-- ============================================================
-- supabase/seeders/08_grading_scale.sql
-- SAMPLE grading scale: the common CHED-style 1.00 to 5.00 scale.
-- Not confirmed against the PLP handbook. Admin can change every band
-- in the app (Admin > Content > Grading).
--
-- Each grade point is its own band (from = to), because a Professor enters
-- the grade point (1.25, 2.00 ...). Descriptive bands are display only.
-- INC and DRP are label bands with no range, typed as text.
-- Does nothing if the scale already has bands.
--
-- grade_bands refuses direct writes (trigger), so the write switch is turned on
-- for this session around the insert and turned off again after it.
-- ============================================================
SELECT set_config('app.grade_write', 'on', false);

INSERT INTO grade_bands (label, outcome, is_descriptive, from_value, to_value, sort_order)
SELECT v.label, v.outcome, v.is_descriptive, v.from_value, v.to_value, v.sort_order
FROM (VALUES
  ('1.00',        'passed',     false, 1.00::numeric, 1.00::numeric,  10),
  ('1.25',        'passed',     false, 1.25, 1.25,  20),
  ('1.50',        'passed',     false, 1.50, 1.50,  30),
  ('1.75',        'passed',     false, 1.75, 1.75,  40),
  ('2.00',        'passed',     false, 2.00, 2.00,  50),
  ('2.25',        'passed',     false, 2.25, 2.25,  60),
  ('2.50',        'passed',     false, 2.50, 2.50,  70),
  ('2.75',        'passed',     false, 2.75, 2.75,  80),
  ('3.00',        'passed',     false, 3.00, 3.00,  90),
  ('4.00',        'failed',     false, 4.00, 4.00, 100),
  ('5.00',        'failed',     false, 5.00, 5.00, 110),
  ('INC',         'incomplete', false, NULL, NULL, 120),
  ('DRP',         'dropped',    false, NULL, NULL, 130),
  ('Excellent',   'passed',     true,  1.00, 1.25, 200),
  ('Very Good',   'passed',     true,  1.50, 1.75, 210),
  ('Good',        'passed',     true,  2.00, 2.25, 220),
  ('Satisfactory','passed',     true,  2.50, 2.75, 230),
  ('Passing',     'passed',     true,  3.00, 3.00, 240)
) AS v(label, outcome, is_descriptive, from_value, to_value, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM grade_bands);

SELECT set_config('app.grade_write', 'off', false);
