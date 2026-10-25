-- ============================================================
-- supabase/seeders/02_faculty_accounts.sql
-- Demo faculty for the BSIT sample schedules (06 and 07).
-- DEMO DATA ONLY: placeholder names, rename them in Admin > Accounts.
-- Password for all: Professor@123 (change before real use).
-- Safe to re-run: an account that already exists is left alone (it may
-- already be assigned to a schedule, so it must not be deleted).
-- Run after 01_staff_accounts.sql (needs the colleges).
-- ============================================================
DO $$
DECLARE
  r record;
  v_auth uuid;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('prof.ccs1@plp.edu.ph',    'Demo Professor CCS 1 (Data Structures)',     'CCS'),
    ('prof.ccs2@plp.edu.ph',    'Demo Professor CCS 2 (Information Mgmt)',    'CCS'),
    ('prof.ccs3@plp.edu.ph',    'Demo Professor CCS 3 (Platform Tech, Discrete Math)', 'CCS'),
    ('prof.ccs4@plp.edu.ph',    'Demo Professor CCS 4 (OOP)',                 'CCS'),
    ('prof.ccs5@plp.edu.ph',    'Demo Professor CCS 5 (Intro to Computing)',  'CCS'),
    ('prof.ccs6@plp.edu.ph',    'Demo Professor CCS 6 (Programming)',         'CCS'),
    ('prof.cas.ge@plp.edu.ph',  'Demo Professor CAS 1 (General Education)',   'CAS'),
    ('prof.cas.ge2@plp.edu.ph', 'Demo Professor CAS 2 (General Education)',   'CAS'),
    ('prof.cas.pe@plp.edu.ph',  'Demo Instructor CAS (PE)',                   'CAS'),
    ('prof.nstp@plp.edu.ph',    'Demo Instructor NSTP',                       'CAS')
  ) AS v(email, full_name, college_code)
  LOOP
    CONTINUE WHEN EXISTS (SELECT 1 FROM auth.users WHERE email = r.email);
    v_auth := gen_random_uuid();

    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_auth, 'authenticated', 'authenticated',
      r.email, extensions.crypt('Professor@123', extensions.gen_salt('bf', 10)), now(),
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
    VALUES (v_auth, r.full_name, r.email, 'professor',
            (SELECT c.id FROM colleges c WHERE c.code = r.college_code));
  END LOOP;
END $$;
