-- supabase/gates_check.sql
-- Local only. Run after `npm run db:reset`: it inserts test fixtures.
-- Checks the gates in 20261025000000_init.sql: capacity, promotion, student number,
-- schedule chain, slip/payment/COR order, reschedule permissions, audit log.
-- Blocked actions print 'ok   blocked'. Any 'FAIL' line is a broken rule.
\set ON_ERROR_STOP on
SET search_path = public, extensions;
-- fixtures (superuser, no actor)
INSERT INTO colleges (id,name,code) VALUES ('00000000-0000-0000-0000-0000000000c1','College of Ed','COE');
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000a1','BSED','Bachelor of Ed','00000000-0000-0000-0000-0000000000c1');
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('admin','ad'),('registrar','rg'),('finance','fn'),('college_secretary','sc'),('dean','dn'),('professor','pf'),('applicant','ap'),('applicant','ap2')) v(role,k) LOOP
    INSERT INTO auth.users (id,email) VALUES (md5(r.k)::uuid, r.k||'@x.ph');
    INSERT INTO users (id,auth_id,full_name,email,role,college_id)
      VALUES (md5(r.k)::uuid, md5(r.k)::uuid, r.k, r.k||'@x.ph', r.role,
              CASE WHEN r.role IN ('dean','college_secretary') THEN '00000000-0000-0000-0000-0000000000c1'::uuid END);
  END LOOP;
  INSERT INTO applicants (id,user_id,applicant_ref,program_id,admission_date,admission_type)
    VALUES (md5('A1')::uuid, md5('ap')::uuid,'ADM-1','00000000-0000-0000-0000-0000000000a1',current_date,'new'),
           (md5('A2')::uuid, md5('ap2')::uuid,'ADM-2','00000000-0000-0000-0000-0000000000a1',current_date,'new');
END $$;
SELECT 'payment setting auto-created', count(*) FROM program_payment_settings;

CREATE OR REPLACE FUNCTION expect_fail(label text, sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql; RAISE NOTICE 'FAIL (should have errored): %', label;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ok   blocked: % -> %', label, left(SQLERRM,70); END;
END $$;
CREATE OR REPLACE FUNCTION act(k text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.actor_id', md5(k)::text, false) $$;

-- visits
SELECT act('rg');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name)
  VALUES (md5('S1')::uuid,'00000000-0000-0000-0000-0000000000a1',current_date+3,'09:00','10:00',1,'Registrar');
INSERT INTO visit_bookings (applicant_id,slot_id) VALUES (md5('A1')::uuid, md5('S1')::uuid);
SELECT expect_fail('slot over capacity', $$INSERT INTO visit_bookings (applicant_id,slot_id) VALUES (md5('A2')::uuid, md5('S1')::uuid)$$);

-- promotion
SELECT act('sc');
SELECT expect_fail('secretary promotes', $$INSERT INTO students (applicant_id,documents_received_by) VALUES (md5('A1')::uuid, md5('sc')::uuid)$$);
SELECT act('rg');
INSERT INTO students (id,applicant_id,student_number,documents_received_by) VALUES (md5('ST1')::uuid, md5('A1')::uuid,'HACKED', md5('rg')::uuid);
SELECT 'number assigned', student_number, (SELECT role FROM users WHERE id=md5('ap')::uuid) AS role_now FROM students;
SELECT expect_fail('edit student number', $$UPDATE students SET student_number='1'$$);

-- schedule chain
SELECT act('sc');
INSERT INTO subjects (id,program_id,code,title,units) VALUES (md5('SUB')::uuid,'00000000-0000-0000-0000-0000000000a1','ED101','Intro',3);
INSERT INTO rooms (id,name) VALUES (md5('R1')::uuid,'Room 1');
INSERT INTO sections (id,program_id,name,year_level) VALUES (md5('SEC')::uuid,'00000000-0000-0000-0000-0000000000a1','A',1);
INSERT INTO section_subjects (section_id,subject_id,professor_id,room_id,day_of_week,start_time,end_time)
  VALUES (md5('SEC')::uuid, md5('SUB')::uuid, md5('pf')::uuid, md5('R1')::uuid, 1,'08:00','09:00');
INSERT INTO subjects (id,program_id,code,title,units) VALUES (md5('SUB2')::uuid,'00000000-0000-0000-0000-0000000000a1','ED102','Two',3);
SELECT expect_fail('room/professor double booked', $$INSERT INTO section_subjects (section_id,subject_id,professor_id,room_id,day_of_week,start_time,end_time) VALUES (md5('SEC')::uuid, md5('SUB2')::uuid, md5('pf')::uuid, md5('R1')::uuid, 1,'08:30','09:30')$$);
SELECT expect_fail('approve before dean', $$UPDATE sections SET schedule_status='approved'$$);
UPDATE sections SET schedule_status='pending_dean';
SELECT expect_fail('secretary signs off', $$UPDATE sections SET schedule_status='dean_signed'$$);
SELECT expect_fail('edit loading after submit', $$UPDATE section_subjects SET room_id=NULL$$);
SELECT act('dn'); UPDATE sections SET schedule_status='dean_signed';
SELECT act('rg'); UPDATE sections SET schedule_status='approved';
SELECT 'section approved', schedule_status, dean_signed_by IS NOT NULL AS dean_stamped, approved_by IS NOT NULL AS reg_stamped FROM sections;
SELECT act('sc'); INSERT INTO student_sections (student_id,section_id) VALUES (md5('ST1')::uuid, md5('SEC')::uuid);

-- slip, payment, COR (toggle on)
SELECT act('fn'); UPDATE program_payment_settings SET payment_required = true;
SELECT act('rg');
SELECT expect_fail('COR before slip', $$INSERT INTO cors (student_id,issued_by) VALUES (md5('ST1')::uuid, md5('rg')::uuid)$$);
INSERT INTO assessment_slips (student_id,payment_required,issued_by) VALUES (md5('ST1')::uuid,false,md5('rg')::uuid);
SELECT 'slip snapshot', payment_required, (SELECT count(*) FROM payments) AS payments_opened FROM assessment_slips;
SELECT expect_fail('COR before payment', $$INSERT INTO cors (student_id,issued_by) VALUES (md5('ST1')::uuid, md5('rg')::uuid)$$);
SELECT act('fn'); UPDATE payments SET amount_due=1000, amount_paid=1000, status='cleared';
SELECT act('rg'); INSERT INTO cors (student_id,issued_by) VALUES (md5('ST1')::uuid, md5('rg')::uuid);
SELECT 'enrolled', count(*) FROM cors;

-- reschedule request: student may file, cannot decide
SELECT act('ap');
INSERT INTO reschedule_requests (booking_id,requested_by,reason) VALUES ((SELECT id FROM visit_bookings),md5('ap')::uuid,'sick');
SELECT expect_fail('student approves own request', $$UPDATE reschedule_requests SET status='approved'$$);
SELECT act('sc'); SELECT expect_fail('secretary mass reschedule', $$INSERT INTO mass_reschedules (affected_date,reason,triggered_by) VALUES (current_date,'x',md5('sc')::uuid)$$);
SELECT act('rg'); INSERT INTO mass_reschedules (affected_date,reason,triggered_by) VALUES (current_date,'typhoon',md5('rg')::uuid);

-- audit
SELECT 'audit rows', count(*), count(DISTINCT table_name) AS tables FROM audit_log;
SELECT 'toggle audited', actor_role, old_data->>'payment_required' AS was, new_data->>'payment_required' AS now FROM audit_log WHERE table_name='program_payment_settings';
SELECT expect_fail('edit audit log', $$UPDATE audit_log SET reason='x'$$);
SELECT expect_fail('delete audit log', $$DELETE FROM audit_log$$);
