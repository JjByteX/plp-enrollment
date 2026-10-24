-- supabase/gates_check.sql
-- Local only. Run after `npm run db:reset`: it inserts test fixtures.
-- Checks the gates in 20261025000000_init.sql: capacity, promotion, student number,
-- schedule chain, slip/payment/COR order, reschedule permissions, audit log.
-- Also checks step 6 in 20261025040000_visit_scheduling.sql: slot guard,
-- next open slot, assign/move, assign all unassigned, notifications, role refusal.
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

-- ============================================================
-- visit scheduling (step 6). Own program BSX so earlier fixtures
-- cannot change the order. Dates are Manila based, like the functions.
-- ============================================================
CREATE OR REPLACE FUNCTION expect_eq(label text, actual text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS NOT DISTINCT FROM expected THEN RAISE NOTICE 'ok   %: %', label, actual;
  ELSE RAISE NOTICE 'FAIL %: got %, expected %', label, actual, expected; END IF;
END $$;
CREATE OR REPLACE FUNCTION mnl_today() RETURNS date LANGUAGE sql AS $$ SELECT (now() AT TIME ZONE 'Asia/Manila')::date $$;
CREATE OR REPLACE FUNCTION mk_applicant(k text, prog uuid, adm date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email) VALUES (md5(k)::uuid, k||'@x.ph');
  INSERT INTO users (id,auth_id,full_name,email,role) VALUES (md5(k)::uuid, md5(k)::uuid, k, k||'@x.ph', 'applicant');
  INSERT INTO applicants (id,user_id,applicant_ref,program_id,admission_date,admission_type)
    VALUES (md5('A'||k)::uuid, md5(k)::uuid, 'ADM-'||k, prog, adm, 'new');
END $$;

SELECT act('ad');
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000a2','BSX','Test Program X','00000000-0000-0000-0000-0000000000c1');
-- b3 is created first but admitted last, b1 admitted first: order must follow admission_date
SELECT mk_applicant('b3','00000000-0000-0000-0000-0000000000a2', mnl_today());
SELECT mk_applicant('b2','00000000-0000-0000-0000-0000000000a2', mnl_today()-1);
SELECT mk_applicant('b1','00000000-0000-0000-0000-0000000000a2', mnl_today()-2);

SELECT act('rg');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring,status) VALUES
  (md5('SA')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+2,'09:00','10:00',1,'Registrar Office','Form 138, PSA birth certificate','open'),
  (md5('SB')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+2,'10:00','11:00',1,'Registrar Office','Form 138, PSA birth certificate','open'),
  (md5('SX')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+2,'08:00','09:00',5,'Registrar Office','x','closed'),
  (md5('SC')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+2,'07:00','08:00',5,'Registrar Office','x','cancelled'),
  (md5('SY')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()-1,'08:00','09:00',5,'Registrar Office','x','open');

-- role refusal: only Registrar and Admin
SELECT act('ap2'); SELECT expect_fail('applicant assigns', $$SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SA')::uuid)$$);
SELECT expect_fail('applicant looks up slot', $$SELECT next_open_slot('00000000-0000-0000-0000-0000000000a2')$$);
SELECT expect_fail('applicant assigns all', $$SELECT assign_unassigned_visits('00000000-0000-0000-0000-0000000000a2')$$);
SELECT act('fn'); SELECT expect_fail('finance assigns', $$SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SA')::uuid)$$);
SELECT act('dn'); SELECT expect_fail('dean assigns', $$SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SA')::uuid)$$);
SELECT act('sc'); SELECT expect_fail('secretary assigns', $$SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SA')::uuid)$$);
SELECT act('ap'); SELECT expect_fail('student assigns', $$SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SA')::uuid)$$);

-- next open slot skips closed, cancelled, ended and other-program slots
SELECT act('rg');
SELECT expect_eq('next open slot is SA', next_open_slot('00000000-0000-0000-0000-0000000000a2')::text, md5('SA')::uuid::text);

-- assign all: 3 applicants, 2 seats, ordered by admission date
SELECT expect_eq('assigned / left over', (SELECT assigned||'/'||left_over FROM assign_unassigned_visits('00000000-0000-0000-0000-0000000000a2')), '2/1');
SELECT expect_eq('b1 (admitted first) in SA', (SELECT slot_id::text FROM visit_bookings WHERE applicant_id=md5('Ab1')::uuid), md5('SA')::uuid::text);
SELECT expect_eq('b2 in SB', (SELECT slot_id::text FROM visit_bookings WHERE applicant_id=md5('Ab2')::uuid), md5('SB')::uuid::text);
SELECT expect_eq('b3 left without a slot', (SELECT count(*)::text FROM visit_bookings WHERE applicant_id=md5('Ab3')::uuid), '0');

-- notification written with the booking, email pending
SELECT expect_eq('b1 notification kind/email', (SELECT kind||'/'||email_status FROM notifications WHERE user_id=md5('b1')::uuid), 'visit_assigned/pending');
SELECT expect_eq('b1 window label', (SELECT window_label FROM notifications WHERE user_id=md5('b1')::uuid), '9:00 AM to 10:00 AM');
SELECT expect_eq('b1 office', (SELECT office_name FROM notifications WHERE user_id=md5('b1')::uuid), 'Registrar Office');
SELECT expect_eq('b1 what to bring', (SELECT what_to_bring FROM notifications WHERE user_id=md5('b1')::uuid), 'Form 138, PSA birth certificate');
SELECT expect_eq('b1 scheduled_for (Manila)', (SELECT scheduled_for::text FROM notifications WHERE user_id=md5('b1')::uuid),
                 (((mnl_today()+2) + time '09:00') AT TIME ZONE 'Asia/Manila')::text);
SELECT expect_eq('b1 booking assigned_by registrar', (SELECT assigned_by::text FROM visit_bookings WHERE applicant_id=md5('Ab1')::uuid), md5('rg')::uuid::text);

-- rejected bookings leave no half written notification
SELECT expect_fail('assign into full slot', $$SELECT assign_visit_slot(md5('Ab3')::uuid, md5('SB')::uuid)$$);
SELECT expect_fail('assign into closed slot', $$SELECT assign_visit_slot(md5('Ab3')::uuid, md5('SX')::uuid)$$);
SELECT expect_fail('assign into cancelled slot', $$SELECT assign_visit_slot(md5('Ab3')::uuid, md5('SC')::uuid)$$);
SELECT expect_fail('assign into other program slot', $$SELECT assign_visit_slot(md5('Ab3')::uuid, md5('S1')::uuid)$$);
SELECT expect_eq('b3 has no booking and no notification',
  (SELECT (SELECT count(*) FROM visit_bookings WHERE applicant_id=md5('Ab3')::uuid)||'/'||(SELECT count(*) FROM notifications WHERE user_id=md5('b3')::uuid)), '0/0');

-- slot guard: capacity floor, cancel with bookings, program change. Admin may assign too.
SELECT mk_applicant('b4','00000000-0000-0000-0000-0000000000a2', mnl_today());
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring)
  VALUES (md5('SG')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+5,'09:00','10:00',2,'Registrar Office','x');
SELECT act('ad');
SELECT assign_visit_slot(md5('Ab3')::uuid, md5('SG')::uuid);
SELECT act('rg');
SELECT assign_visit_slot(md5('Ab4')::uuid, md5('SG')::uuid);
SELECT expect_eq('admin booking assigned_by admin', (SELECT assigned_by::text FROM visit_bookings WHERE applicant_id=md5('Ab3')::uuid), md5('ad')::uuid::text);
SELECT expect_fail('capacity below booked', $$UPDATE visit_slots SET capacity=1 WHERE id=md5('SG')::uuid$$);
SELECT expect_fail('cancel slot with bookings', $$UPDATE visit_slots SET status='cancelled' WHERE id=md5('SG')::uuid$$);
SELECT expect_fail('change program of booked slot', $$UPDATE visit_slots SET program_id='00000000-0000-0000-0000-0000000000a1' WHERE id=md5('SG')::uuid$$);
SELECT expect_fail('change date of booked slot', $$UPDATE visit_slots SET slot_date=slot_date+1 WHERE id=md5('SG')::uuid$$);
SELECT expect_fail('change time of booked slot', $$UPDATE visit_slots SET start_time='08:00' WHERE id=md5('SG')::uuid$$);
SELECT expect_fail('change office of booked slot', $$UPDATE visit_slots SET office_name='Elsewhere' WHERE id=md5('SG')::uuid$$);
UPDATE visit_slots SET what_to_bring='Updated list' WHERE id=md5('SG')::uuid;
SELECT expect_eq('what to bring of booked slot can change', (SELECT what_to_bring FROM visit_slots WHERE id=md5('SG')::uuid), 'Updated list');
UPDATE visit_slots SET status='closed' WHERE id=md5('SG')::uuid;
SELECT expect_eq('slot with bookings can be closed', (SELECT status FROM visit_slots WHERE id=md5('SG')::uuid), 'closed');
UPDATE visit_slots SET status='open' WHERE id=md5('SG')::uuid;

-- move: same booking row, new slot, reason in audit log, visit_moved notification
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring)
  VALUES (md5('SM')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+3,'09:00','10:00',1,'Registrar Office','x'),
         (md5('SN')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+4,'09:00','10:00',1,'Registrar Office','x');
SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SM')::uuid, 'typhoon');
SELECT expect_eq('move keeps one booking row', (SELECT count(*)::text FROM visit_bookings WHERE applicant_id=md5('Ab1')::uuid), '1');
SELECT expect_eq('move changed slot', (SELECT slot_id::text FROM visit_bookings WHERE applicant_id=md5('Ab1')::uuid), md5('SM')::uuid::text);
SELECT expect_eq('move notification', (SELECT count(*)::text FROM notifications WHERE user_id=md5('b1')::uuid AND kind='visit_moved' AND email_status='pending'), '1');
SELECT expect_eq('move audit reason + actor', (SELECT reason||'/'||(actor_id = md5('rg')::uuid)::text FROM audit_log
  WHERE table_name='visit_bookings' AND action='UPDATE' AND new_data->>'applicant_id' = md5('Ab1')::uuid::text AND new_data->>'slot_id' = md5('SM')::uuid::text), 'typhoon/true');
SELECT expect_fail('move into the same slot', $$SELECT assign_visit_slot(md5('Ab1')::uuid, md5('SM')::uuid)$$);
SELECT expect_eq('student number and role untouched by move', (SELECT count(*)::text FROM students), '1');

-- a visit already marked attended cannot be moved, and the reason does not leak to the next change
UPDATE visit_bookings SET status='attended' WHERE applicant_id=md5('Ab2')::uuid;
SELECT expect_fail('move an attended visit', $$SELECT assign_visit_slot(md5('Ab2')::uuid, md5('SN')::uuid)$$);
SELECT expect_eq('audit reason does not leak', (SELECT coalesce(reason,'none') FROM audit_log
  WHERE table_name='visit_bookings' AND action='UPDATE' AND new_data->>'status'='attended' AND new_data->>'applicant_id' = md5('Ab2')::uuid::text), 'none');

-- audit
SELECT 'audit rows', count(*), count(DISTINCT table_name) AS tables FROM audit_log;
SELECT 'toggle audited', actor_role, old_data->>'payment_required' AS was, new_data->>'payment_required' AS now FROM audit_log WHERE table_name='program_payment_settings';
SELECT expect_fail('edit audit log', $$UPDATE audit_log SET reason='x'$$);
SELECT expect_fail('delete audit log', $$DELETE FROM audit_log$$);
