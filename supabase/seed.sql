-- ============================================================
-- supabase/seed.sql
-- Demo accounts for PLP Enrollment (same idea as PLP Admissions' seed_users.sql).
-- Runs automatically on `supabase db reset`. For a hosted project, paste it
-- into the Supabase SQL editor once, after the migrations have been applied.
--
-- DEMO DATA ONLY. Change every password before real use.
--
-- Default passwords:
--   admin@plp.edu.ph               -> Admin@123
--   registrar@plp.edu.ph           -> Registrar@123
--   finance@plp.edu.ph             -> Finance@123
--   dean.<college>@plp.edu.ph      -> Dean@123
--   secretary.<college>@plp.edu.ph -> Secretary@123
--   professor.<college>@plp.edu.ph -> Professor@123
--   <college> = ccs, con, cba, coe, cas, cen, hm
--
-- Safe to re-run: the seeded accounts are removed first (deleting the auth
-- user also removes its users row). Applicants and students are not seeded:
-- they come from the Admissions intake.
-- ============================================================

-- Colleges (already created by the migrations; this keeps the seed standalone)
INSERT INTO colleges (code, name) VALUES
    ('CCS', 'College of Computer Studies'),
    ('CON', 'College of Nursing'),
    ('CBA', 'College of Business and Accountancy'),
    ('COE', 'College of Education'),
    ('CAS', 'College of Arts and Sciences'),
    ('CEN', 'College of Engineering'),
    ('HM', 'College of Hospitality Management')
ON CONFLICT (code) DO NOTHING;

DELETE FROM auth.users WHERE email IN (
    'admin@plp.edu.ph',
    'registrar@plp.edu.ph',
    'finance@plp.edu.ph',
    'dean.ccs@plp.edu.ph',
    'dean.con@plp.edu.ph',
    'dean.cba@plp.edu.ph',
    'dean.coe@plp.edu.ph',
    'dean.cas@plp.edu.ph',
    'dean.cen@plp.edu.ph',
    'dean.hm@plp.edu.ph',
    'secretary.ccs@plp.edu.ph',
    'secretary.con@plp.edu.ph',
    'secretary.cba@plp.edu.ph',
    'secretary.coe@plp.edu.ph',
    'secretary.cas@plp.edu.ph',
    'secretary.cen@plp.edu.ph',
    'secretary.hm@plp.edu.ph',
    'professor.ccs@plp.edu.ph',
    'professor.con@plp.edu.ph',
    'professor.cba@plp.edu.ph',
    'professor.coe@plp.edu.ph',
    'professor.cas@plp.edu.ph',
    'professor.cen@plp.edu.ph',
    'professor.hm@plp.edu.ph'
);

-- Seeded accounts. Each row: email, full name, role, college code (blank = none), password.
DO $$
DECLARE
  r record;
  v_auth uuid;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('admin@plp.edu.ph', 'System Administrator', 'admin', NULL, 'Admin@123'),
    ('registrar@plp.edu.ph', 'Registrar Office', 'registrar', NULL, 'Registrar@123'),
    ('finance@plp.edu.ph', 'Finance Office', 'finance', NULL, 'Finance@123'),
    ('dean.ccs@plp.edu.ph', 'CCS Dean', 'dean', 'CCS', 'Dean@123'),
    ('dean.con@plp.edu.ph', 'CON Dean', 'dean', 'CON', 'Dean@123'),
    ('dean.cba@plp.edu.ph', 'CBA Dean', 'dean', 'CBA', 'Dean@123'),
    ('dean.coe@plp.edu.ph', 'COE Dean', 'dean', 'COE', 'Dean@123'),
    ('dean.cas@plp.edu.ph', 'CAS Dean', 'dean', 'CAS', 'Dean@123'),
    ('dean.cen@plp.edu.ph', 'CEN Dean', 'dean', 'CEN', 'Dean@123'),
    ('dean.hm@plp.edu.ph', 'HM Dean', 'dean', 'HM', 'Dean@123'),
    ('secretary.ccs@plp.edu.ph', 'CCS Secretary', 'college_secretary', 'CCS', 'Secretary@123'),
    ('secretary.con@plp.edu.ph', 'CON Secretary', 'college_secretary', 'CON', 'Secretary@123'),
    ('secretary.cba@plp.edu.ph', 'CBA Secretary', 'college_secretary', 'CBA', 'Secretary@123'),
    ('secretary.coe@plp.edu.ph', 'COE Secretary', 'college_secretary', 'COE', 'Secretary@123'),
    ('secretary.cas@plp.edu.ph', 'CAS Secretary', 'college_secretary', 'CAS', 'Secretary@123'),
    ('secretary.cen@plp.edu.ph', 'CEN Secretary', 'college_secretary', 'CEN', 'Secretary@123'),
    ('secretary.hm@plp.edu.ph', 'HM Secretary', 'college_secretary', 'HM', 'Secretary@123'),
    ('professor.ccs@plp.edu.ph', 'CCS Professor', 'professor', 'CCS', 'Professor@123'),
    ('professor.con@plp.edu.ph', 'CON Professor', 'professor', 'CON', 'Professor@123'),
    ('professor.cba@plp.edu.ph', 'CBA Professor', 'professor', 'CBA', 'Professor@123'),
    ('professor.coe@plp.edu.ph', 'COE Professor', 'professor', 'COE', 'Professor@123'),
    ('professor.cas@plp.edu.ph', 'CAS Professor', 'professor', 'CAS', 'Professor@123'),
    ('professor.cen@plp.edu.ph', 'CEN Professor', 'professor', 'CEN', 'Professor@123'),
    ('professor.hm@plp.edu.ph', 'HM Professor', 'professor', 'HM', 'Professor@123')
  ) AS v(email, full_name, role, college_code, password)
  LOOP
    v_auth := gen_random_uuid();

    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_auth, 'authenticated', 'authenticated',
      r.email, extensions.crypt(r.password, extensions.gen_salt('bf', 10)), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', r.full_name),
      now(), now(), '', '', '', ''
    );

    INSERT INTO auth.identities (
      id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_auth, v_auth::text, 'email',
      jsonb_build_object('sub', v_auth::text, 'email', r.email, 'email_verified', true),
      now(), now(), now()
    );

    INSERT INTO users (auth_id, full_name, email, role, college_id)
    VALUES (
      v_auth, r.full_name, r.email, r.role,
      (SELECT c.id FROM colleges c WHERE c.code = r.college_code)
    );
  END LOOP;
END $$;
