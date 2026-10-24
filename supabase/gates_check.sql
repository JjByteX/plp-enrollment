-- supabase/gates_check.sql
-- Local only. Run after `npm run db:reset`: it inserts test fixtures.
-- Checks the gates in 20261025000000_init.sql: capacity, promotion, student number,
-- schedule chain, slip/payment/COR order, reschedule permissions, audit log.
-- Also checks step 6 in 20261025040000_visit_scheduling.sql: slot guard,
-- next open slot, assign/move, assign all unassigned, notifications, role refusal.
-- Also checks step 7 in 20261025050000_documents_and_numbering.sql: checklist per admission
-- type, mark documents received (hard gate, late items, numbering, booking, notification),
-- locks after promotion, role refusal and row level security. Step 7 also adds
-- my_open_late_items in 20261025060000_my_open_late_items.sql.
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
SELECT expect_eq('b1 what to bring (type checklist, then slot notes)', (SELECT what_to_bring FROM notifications WHERE user_id=md5('b1')::uuid), document_checklist_text('new') || E'\n\n' || 'Form 138, PSA birth certificate');
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

-- ============================================================
-- documents and numbering (step 7), 20261025050000_documents_and_numbering.sql.
-- Applicants d1..d7 in program BSX. Each type gets its own applicant so the
-- checklist per admission type is checked. A refused promotion must not
-- burn a student number (counter snapshot) and must leave nothing behind.
-- ============================================================
CREATE OR REPLACE FUNCTION expect_msg(label text, sql text, frag text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql;
    RAISE NOTICE 'FAIL (should have errored): %', label;
    RETURN;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%' || frag || '%' THEN RAISE NOTICE 'ok   blocked: % -> %', label, left(SQLERRM,90);
    ELSE RAISE NOTICE 'FAIL %: wrong message: %', label, SQLERRM; END IF;
  END;
END $$;
CREATE OR REPLACE FUNCTION mk_applicant_t(k text, prog uuid, adm date, atype text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email) VALUES (md5(k)::uuid, k||'@x.ph');
  INSERT INTO users (id,auth_id,full_name,email,role) VALUES (md5(k)::uuid, md5(k)::uuid, k, k||'@x.ph', 'applicant');
  INSERT INTO applicants (id,user_id,applicant_ref,program_id,admission_date,admission_type)
    VALUES (md5('A'||k)::uuid, md5(k)::uuid, 'ADM-'||k, prog, adm, atype);
END $$;
-- Tick documents for an applicant as the current actor. 'other' gets a note.
CREATE OR REPLACE FUNCTION tick(k text, types text[]) RETURNS void LANGUAGE sql AS $$
  INSERT INTO documents (applicant_id, doc_type, note)
  SELECT md5('A'||k)::uuid, t, CASE WHEN t = 'other' THEN 'extra paper' END FROM unnest(types) t
$$;

SELECT act('ad');
SELECT mk_applicant_t('d1','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'new');
SELECT mk_applicant_t('d2','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'new');
SELECT mk_applicant_t('d3','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'transferee');
SELECT mk_applicant_t('d4','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'foreign');
SELECT mk_applicant_t('d5','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'new');
SELECT mk_applicant_t('d6','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'transferee');
SELECT mk_applicant_t('d7','00000000-0000-0000-0000-0000000000a2', mnl_today(), 'new');

-- catalog: exactly the seeded rows per admission type, late and optional rows not counted as required
SELECT expect_eq('required items, new',        (SELECT count(*)::text FROM document_requirements WHERE active AND required AND 'new' = ANY(applies_to)), '6');
SELECT expect_eq('required items, transferee', (SELECT count(*)::text FROM document_requirements WHERE active AND required AND 'transferee' = ANY(applies_to)), '6');
SELECT expect_eq('required items, foreign',    (SELECT count(*)::text FROM document_requirements WHERE active AND required AND 'foreign' = ANY(applies_to)), '8');
SELECT expect_eq('late items (form_137 only)', (SELECT string_agg(doc_type, ',' ORDER BY doc_type) FROM document_requirements WHERE active AND NOT required AND doc_type <> 'other'), 'form_137');
SELECT expect_eq('checklist lines, new (header + 6 + late)',        (SELECT array_length(string_to_array(document_checklist_text('new'), E'\n'), 1)::text), '8');
SELECT expect_eq('checklist lines, transferee (header + 6)',        (SELECT array_length(string_to_array(document_checklist_text('transferee'), E'\n'), 1)::text), '7');
SELECT expect_eq('checklist lines, foreign (header + 8)',           (SELECT array_length(string_to_array(document_checklist_text('foreign'), E'\n'), 1)::text), '9');
SELECT expect_eq('new list marks Form 137 as later', (document_checklist_text('new') LIKE '%Form 137%(can be submitted later)'), 'true');
SELECT expect_eq('transferee list has no Form 138 and no Form 137', (document_checklist_text('transferee') LIKE '%Form 13%'), 'false');
SELECT expect_eq('foreign list has no valid IDs', (document_checklist_text('foreign') LIKE '%valid IDs%'), 'false');
SELECT expect_eq('unknown type has no list', coalesce(document_checklist_text('nope'), 'null'), 'null');

-- assign_visit_slot: what to bring = checklist for the type, then slot notes when there are any
SELECT act('rg');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring) VALUES
  (md5('SD')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+6,'09:00','10:00',10,'Registrar Office','Extra note'),
  (md5('SE')::uuid,'00000000-0000-0000-0000-0000000000a2',mnl_today()+6,'10:00','11:00',10,'Registrar Office',NULL);
SELECT assign_visit_slot(md5('Ad6')::uuid, md5('SD')::uuid);
SELECT assign_visit_slot(md5('Ad7')::uuid, md5('SE')::uuid);
SELECT expect_eq('transferee notification = list + slot notes',
  (SELECT what_to_bring FROM notifications WHERE user_id=md5('d6')::uuid), document_checklist_text('transferee') || E'\n\n' || 'Extra note');
SELECT expect_eq('transferee notification mentions TOR, not Form 138',
  (SELECT (what_to_bring LIKE '%TOR marked%' AND what_to_bring NOT LIKE '%Form 138%')::text FROM notifications WHERE user_id=md5('d6')::uuid), 'true');
SELECT expect_eq('slot without notes: notification = list only',
  (SELECT what_to_bring FROM notifications WHERE user_id=md5('d7')::uuid), document_checklist_text('new'));
SELECT expect_eq('assign kinds unchanged', (SELECT string_agg(kind, ',') FROM notifications WHERE user_id IN (md5('d6')::uuid, md5('d7')::uuid)), 'visit_assigned,visit_assigned');

-- bookings for the promotion cases: d1 booked, d2 none, d3 attended, d4 no_show
INSERT INTO visit_bookings (applicant_id, slot_id) VALUES (md5('Ad1')::uuid, md5('SD')::uuid);
INSERT INTO visit_bookings (applicant_id, slot_id, status) VALUES (md5('Ad3')::uuid, md5('SD')::uuid, 'attended'), (md5('Ad4')::uuid, md5('SD')::uuid, 'no_show');

-- who may call mark_documents_received: Registrar and Admin only
SELECT tick('d5', ARRAY['endorsement_slip','psa_birth_cert','photo_2x2','student_info_form','valid_ids','form_138']);
SELECT act('ap2'); SELECT expect_msg('applicant marks received', $$SELECT mark_documents_received(md5('Ad5')::uuid)$$, 'Only the Registrar or Admin');
SELECT act('ap');  SELECT expect_msg('student marks received',   $$SELECT mark_documents_received(md5('Ad5')::uuid)$$, 'Only the Registrar or Admin');
SELECT act('fn');  SELECT expect_msg('finance marks received',   $$SELECT mark_documents_received(md5('Ad5')::uuid)$$, 'Only the Registrar or Admin');
SELECT act('dn');  SELECT expect_msg('dean marks received',      $$SELECT mark_documents_received(md5('Ad5')::uuid)$$, 'Only the Registrar or Admin');
SELECT act('sc');  SELECT expect_msg('secretary marks received', $$SELECT mark_documents_received(md5('Ad5')::uuid)$$, 'Only the Registrar or Admin');
SELECT act('pf');  SELECT expect_msg('professor marks received', $$SELECT mark_documents_received(md5('Ad5')::uuid)$$, 'Only the Registrar or Admin');
SELECT expect_eq('d5 still an applicant after refusals', (SELECT (SELECT count(*) FROM students WHERE applicant_id=md5('Ad5')::uuid)||'/'||(SELECT role FROM users WHERE id=md5('d5')::uuid)), '0/applicant');

-- checklist rules on the documents table
SELECT act('rg');
SELECT expect_fail('duplicate tick', $$SELECT tick('d5', ARRAY['psa_birth_cert'])$$);
SELECT expect_fail('tick a document that does not apply (Form 138 for a transferee)', $$SELECT tick('d6', ARRAY['form_138'])$$);
SELECT expect_fail('tick a document that does not apply (passport for new)', $$SELECT tick('d5', ARRAY['passport'])$$);
SELECT expect_fail('other without a note', $$INSERT INTO documents (applicant_id, doc_type) VALUES (md5('Ad5')::uuid, 'other')$$);
SELECT expect_fail('unknown document type', $$INSERT INTO documents (applicant_id, doc_type) VALUES (md5('Ad5')::uuid, 'selfie')$$);
SELECT expect_fail('move a tick to another applicant', $$UPDATE documents SET applicant_id=md5('Ad7')::uuid WHERE applicant_id=md5('Ad5')::uuid AND doc_type='psa_birth_cert'$$);
SELECT expect_fail('change the type of a tick', $$UPDATE documents SET doc_type='photo_2x2' WHERE applicant_id=md5('Ad5')::uuid AND doc_type='psa_birth_cert'$$);
SELECT expect_eq('received_by is stamped, not typed', (SELECT count(*)::text FROM documents WHERE applicant_id=md5('Ad5')::uuid AND received_by = md5('rg')::uuid), '6');
UPDATE documents SET note='checked twice' WHERE applicant_id=md5('Ad5')::uuid AND doc_type='psa_birth_cert';
SELECT expect_eq('note edit keeps received_by', (SELECT received_by::text FROM documents WHERE applicant_id=md5('Ad5')::uuid AND doc_type='psa_birth_cert'), md5('rg')::uuid::text);

-- missing required documents block promotion, name the paper, and burn nothing
CREATE TEMP TABLE snap AS SELECT 'counter'::text AS k, coalesce(sum(last_number),0)::text AS v FROM student_number_counters;
SELECT tick('d1', ARRAY['endorsement_slip','psa_birth_cert','photo_2x2','student_info_form','valid_ids']);
SELECT expect_msg('promote with Form 138 missing', $$SELECT mark_documents_received(md5('Ad1')::uuid)$$, 'Form 138');
SELECT expect_msg('promote with nothing ticked (d2)', $$SELECT mark_documents_received(md5('Ad2')::uuid)$$, 'Endorsement Slip');
SELECT act('ad');
SELECT expect_msg('admin has no override either', $$SELECT mark_documents_received(md5('Ad1')::uuid)$$, 'Still missing');
SELECT act('rg');
SELECT expect_eq('refusals burned no number', (SELECT coalesce(sum(last_number),0)::text FROM student_number_counters), (SELECT v FROM snap WHERE k='counter'));
SELECT expect_eq('refusals left nothing behind',
  (SELECT (SELECT count(*) FROM students WHERE applicant_id IN (md5('Ad1')::uuid, md5('Ad2')::uuid))||'/'||
          (SELECT status FROM visit_bookings WHERE applicant_id=md5('Ad1')::uuid)||'/'||
          (SELECT count(*) FROM notifications WHERE kind='documents_received')), '0/booked/0');
SELECT expect_msg('applicant not found', $$SELECT mark_documents_received(md5('nobody')::uuid)$$, 'Applicant not found');

-- d1: Form 137 is late, so it does not block
SELECT tick('d1', ARRAY['form_138']);
SELECT expect_eq('d1 audit: ticks carry the registrar', (SELECT count(*)::text FROM audit_log
  WHERE table_name='documents' AND action='INSERT' AND actor_id=md5('rg')::uuid AND new_data->>'applicant_id'=md5('Ad1')::uuid::text), '6');
SELECT mark_documents_received(md5('Ad1')::uuid);
SELECT expect_eq('d1 exactly one student row', (SELECT count(*)::text FROM students WHERE applicant_id=md5('Ad1')::uuid), '1');
SELECT expect_eq('d1 number format YY-NNNNN', (SELECT (student_number ~ '^[0-9]{2}-[0-9]{5}$')::text FROM students WHERE applicant_id=md5('Ad1')::uuid), 'true');
SELECT expect_eq('d1 number is the counter value', (SELECT right(student_number,5)::int::text FROM students WHERE applicant_id=md5('Ad1')::uuid),
  (SELECT last_number::text FROM student_number_counters WHERE year = extract(year FROM (now() AT TIME ZONE 'Asia/Manila'))::smallint));
SELECT expect_eq('d1 role is student', (SELECT role FROM users WHERE id=md5('d1')::uuid), 'student');
SELECT expect_eq('d1 stamped by registrar', (SELECT documents_received_by::text FROM students WHERE applicant_id=md5('Ad1')::uuid), md5('rg')::uuid::text);
SELECT expect_eq('d1 booked visit became attended', (SELECT status FROM visit_bookings WHERE applicant_id=md5('Ad1')::uuid), 'attended');
SELECT expect_eq('d1 one pending notification', (SELECT count(*)::text||'/'||min(email_status) FROM notifications WHERE user_id=md5('d1')::uuid AND kind='documents_received'), '1/pending');
SELECT expect_eq('d1 notification has the number and the open late item',
  (SELECT (n.message LIKE '%' || s.student_number || '%' AND n.message LIKE '%Form 137%')::text
     FROM notifications n, students s WHERE n.user_id=md5('d1')::uuid AND n.kind='documents_received' AND s.applicant_id=md5('Ad1')::uuid), 'true');
SELECT expect_eq('d1 promotion audited with the registrar', (SELECT actor_id::text FROM audit_log
  WHERE table_name='students' AND action='INSERT' AND new_data->>'applicant_id'=md5('Ad1')::uuid::text), md5('rg')::uuid::text);
SELECT expect_msg('promote d1 again', $$SELECT mark_documents_received(md5('Ad1')::uuid)$$, 'already a student');
SELECT act('ad');
SELECT expect_msg('admin promotes d1 again', $$SELECT mark_documents_received(md5('Ad1')::uuid)$$, 'already a student');
SELECT expect_fail('edit d1 student number', $$UPDATE students SET student_number='99-99999' WHERE applicant_id=md5('Ad1')::uuid$$);
UPDATE snap SET v = (SELECT coalesce(sum(last_number),0)::text FROM student_number_counters) WHERE k='counter';

-- after promotion: required items locked (Admin too), late items still tickable
SELECT expect_fail('admin deletes a required tick after promotion', $$DELETE FROM documents WHERE applicant_id=md5('Ad1')::uuid AND doc_type='psa_birth_cert'$$);
SELECT expect_fail('admin edits a required tick note after promotion', $$UPDATE documents SET note='x' WHERE applicant_id=md5('Ad1')::uuid AND doc_type='psa_birth_cert'$$);
SELECT act('rg');
SELECT expect_fail('registrar deletes a required tick after promotion', $$DELETE FROM documents WHERE applicant_id=md5('Ad1')::uuid AND doc_type='form_138'$$);
SELECT tick('d1', ARRAY['form_137']);
SELECT expect_eq('late item ticked after promotion', (SELECT count(*)::text FROM documents WHERE applicant_id=md5('Ad1')::uuid AND doc_type='form_137'), '1');
SELECT tick('d1', ARRAY['other']);
SELECT expect_eq('optional other ticked after promotion', (SELECT count(*)::text FROM documents WHERE applicant_id=md5('Ad1')::uuid AND doc_type='other'), '1');
DELETE FROM documents WHERE applicant_id=md5('Ad1')::uuid AND doc_type='form_137';
SELECT expect_eq('late item can be unticked after promotion', (SELECT count(*)::text FROM documents WHERE applicant_id=md5('Ad1')::uuid AND doc_type='form_137'), '0');
SELECT expect_eq('d1 required ticks all still there', (SELECT count(*)::text FROM documents d JOIN document_requirements r USING (doc_type) WHERE d.applicant_id=md5('Ad1')::uuid AND r.required), '6');

-- d2: no visit booking, promotion still works, no booking is invented
SELECT tick('d2', ARRAY['endorsement_slip','psa_birth_cert','photo_2x2','student_info_form','valid_ids','form_138']);
SELECT mark_documents_received(md5('Ad2')::uuid);
SELECT expect_eq('d2 promoted without a booking', (SELECT (SELECT count(*) FROM students WHERE applicant_id=md5('Ad2')::uuid)||'/'||(SELECT count(*) FROM visit_bookings WHERE applicant_id=md5('Ad2')::uuid)), '1/0');
SELECT expect_eq('d2 number follows d1 (nothing burned between)',
  (SELECT (right(b.student_number,5)::int - right(a.student_number,5)::int)::text FROM students a, students b WHERE a.applicant_id=md5('Ad1')::uuid AND b.applicant_id=md5('Ad2')::uuid), '1');

-- d3 transferee: needs TOR, not Form 138. Attended booking stays attended.
SELECT tick('d3', ARRAY['endorsement_slip','psa_birth_cert','photo_2x2','student_info_form','valid_ids']);
SELECT expect_msg('transferee without TOR', $$SELECT mark_documents_received(md5('Ad3')::uuid)$$, 'TOR');
SELECT tick('d3', ARRAY['tor']);
SELECT mark_documents_received(md5('Ad3')::uuid);
SELECT expect_eq('d3 promoted, attended stays attended', (SELECT (SELECT count(*) FROM students WHERE applicant_id=md5('Ad3')::uuid)||'/'||(SELECT status FROM visit_bookings WHERE applicant_id=md5('Ad3')::uuid)), '1/attended');
SELECT expect_eq('d3 has no late items in its message', (SELECT (message LIKE '%Still to submit%')::text FROM notifications WHERE user_id=md5('d3')::uuid AND kind='documents_received'), 'false');

-- d4 foreign, promoted by Admin: passport, visa, ACR and TOR, no valid IDs. no_show stays no_show.
SELECT act('ad');
SELECT tick('d4', ARRAY['endorsement_slip','psa_birth_cert','photo_2x2','student_info_form','tor','passport','visa_permit']);
SELECT expect_msg('foreign without ACR', $$SELECT mark_documents_received(md5('Ad4')::uuid)$$, 'Alien Certificate of Registration');
SELECT tick('d4', ARRAY['acr']);
SELECT mark_documents_received(md5('Ad4')::uuid);
SELECT expect_eq('d4 promoted by admin, no_show stays', (SELECT (SELECT count(*) FROM students WHERE applicant_id=md5('Ad4')::uuid)||'/'||(SELECT status FROM visit_bookings WHERE applicant_id=md5('Ad4')::uuid)||'/'||(SELECT documents_received_by::text FROM students WHERE applicant_id=md5('Ad4')::uuid)), '1/no_show/' || md5('ad')::uuid::text);
SELECT expect_eq('three promotions after the snapshot used three numbers',
  (SELECT sum(last_number)::int - (SELECT v::int FROM snap WHERE k='counter') FROM student_number_counters), '3');

-- row level security as the signed-in roles (skipped when the role does not exist)
SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') AS has_auth \gset
\if :has_auth
SET ROLE authenticated;
SELECT act('ap2');
SELECT expect_eq('applicant sees no documents', (SELECT count(*)::text FROM documents), '0');
SELECT expect_fail('applicant ticks a document', $$INSERT INTO documents (applicant_id, doc_type) VALUES (md5('Ad7')::uuid, 'psa_birth_cert')$$);
SELECT expect_eq('applicant can read the catalog', ((SELECT count(*) FROM document_requirements) > 0)::text, 'true');
SELECT act('fn');
SELECT expect_eq('finance sees no documents', (SELECT count(*)::text FROM documents), '0');
SELECT act('sc');
SELECT expect_eq('secretary sees no documents', (SELECT count(*)::text FROM documents), '0');
SELECT act('rg');
SELECT expect_eq('registrar sees documents', ((SELECT count(*) FROM documents) > 0)::text, 'true');
SELECT expect_fail('registrar writes the catalog', $$INSERT INTO document_requirements (doc_type, label, applies_to) VALUES ('x_doc','X',ARRAY['new'])$$);
SELECT act('ad');
SELECT expect_eq('admin sees documents', ((SELECT count(*) FROM documents) > 0)::text, 'true');
INSERT INTO document_requirements (doc_type, label, applies_to, required, sort_order) VALUES ('x_doc','X',ARRAY['new'],false,900);
SELECT expect_eq('admin writes the catalog', (SELECT count(*)::text FROM document_requirements WHERE doc_type='x_doc'), '1');
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, row level security checks not run';
\endif
-- catalog and checklist changes are audited with the actor
SELECT expect_eq('catalog write audited', (SELECT count(*)::text FROM audit_log WHERE table_name='document_requirements' AND action='INSERT' AND actor_id=md5('ad')::uuid AND new_data->>'doc_type'='x_doc'), CASE WHEN :'has_auth' = 't' THEN '1' ELSE '0' END);

-- my_open_late_items (20261025060000): a student sees only their own open late items
SELECT act('d1');
SELECT expect_eq('d1 sees Form 137 as open', (SELECT (array_length(my_open_late_items(), 1) = 1 AND my_open_late_items()[1] LIKE '%Form 137%')::text), 'true');
SELECT act('d3');
SELECT expect_eq('d3 (transferee) has no late items', (SELECT cardinality(my_open_late_items())::text), '0');
SELECT act('rg');
SELECT expect_eq('registrar gets an empty list', (SELECT cardinality(my_open_late_items())::text), '0');
SELECT act('ap2');
SELECT expect_eq('applicant gets an empty list', (SELECT cardinality(my_open_late_items())::text), '0');
SELECT act('rg');
SELECT tick('d1', ARRAY['form_137']);
SELECT act('d1');
SELECT expect_eq('d1 late item closes once ticked', (SELECT cardinality(my_open_late_items())::text), '0');

-- audit
SELECT 'audit rows', count(*), count(DISTINCT table_name) AS tables FROM audit_log;
SELECT 'toggle audited', actor_role, old_data->>'payment_required' AS was, new_data->>'payment_required' AS now FROM audit_log WHERE table_name='program_payment_settings';
SELECT expect_fail('edit audit log', $$UPDATE audit_log SET reason='x'$$);
SELECT expect_fail('delete audit log', $$DELETE FROM audit_log$$);
