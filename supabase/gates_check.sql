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
-- Also checks step 8 in 20261025070000_section_scheduling.sql: subjects filling a new section,
-- loading rules (professor, room, time clashes, program and college), the Secretary / Dean /
-- Registrar chain with rejection back to draft, automatic placement and capacity, moving a
-- student, notifications, role refusal and row level security.
-- Also checks step 9 in 20261025080000_assessment_slip.sql: issue one slip (schedule gate, once only,
-- notification, payment snapshot), issue all ready, and who may read a slip's content.
-- Also checks the laboratory meetings in 20261025090000_laboratory_meetings.sql: a lecture and a
-- laboratory row per subject, filled automatically, and units counted once on the slip.
-- Also checks step 12 in 20261025120000_reschedules.sql: next open slot with an excluded date and
-- office, the mass reschedule (role refusal, input refusals, one office, a whole date, run again after
-- adding slots, attended and no show left alone), the applicant request, and the Registrar's approve
-- or decline (notifications, audit, rolled back refusals, row level security).
-- Also checks step 16 in 20261025180000_schedule_changes.sql: the slip and COR keep their own saved
-- schedule, amend_schedule (roles, college, reason, draft, clashes, notifications, audit), the lock once
-- a COR exists, my_schedule_changed and the function grants.
-- Also checks step 18 in 20261026010000_terms_foundation.sql: the term on subjects, sections and
-- enrollments, a section only once the term is set, one slip, payment and COR per student per term,
-- and the placement and move rules across terms. The term is set at the top of the fixtures because a
-- section needs it. The one earlier expectation that changed: a COR carries the term of the student's
-- enrollment, not the term current on the day it is issued.
-- Also checks step 19 in 20261026020000_grading.sql: the grading scale (overlap refused, one outcome per
-- grade), grade entry and the draft, submitted, approved sheet, the Dean's approval, the INC lapse, and a
-- grade change through the Professor, the Dean and the Registrar.
-- Also checks step 20 in 20261026040000_prerequisites_and_credits.sql: who may set prerequisites, the refusals
-- (itself, another program, not earlier, no year level), eligibility (failed, incomplete, dropped, never taken
-- and an unapproved sheet block; a pass, a passing retake and an approved credit unblock), credits (record,
-- approve, reject, record again), what each role may read, refusing to delete a subject that others require,
-- the audit rows and the function grants.
-- Also checks step 21 in 20261026050000_close_term.sql: closing a term (who may, refused while a section subject has no
-- Dean-approved grades, once only), the result of each student (promote, review with the reason, completed, withdrawn
-- skipped), the review and completed lists, the advising flag, and opening the next term (sections copied, the promoted
-- student seated and told, nobody placed twice, the school year rollover, the function grants).
-- Blocked actions print 'ok   blocked'. Any 'FAIL' line is a broken rule.
\set ON_ERROR_STOP on
SET search_path = public, extensions;
-- The migrations seed the 7 colleges and 13 programs; the fixtures below need those codes free.
-- Local only: run `npm run db:reset` again afterward to get the seeded rows back.
DELETE FROM programs;
DELETE FROM colleges;
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

-- the term (step 18): a section takes the current term, so Admin sets it before any section exists
SELECT act('ad'); INSERT INTO enrollment_term (school_year, semester) VALUES ('2026-2027','1st');

-- schedule chain
SELECT act('sc');
INSERT INTO subjects (id,program_id,code,title,units) VALUES (md5('SUB')::uuid,'00000000-0000-0000-0000-0000000000a1','ED101','Intro',3);
INSERT INTO rooms (id,name) VALUES (md5('R1')::uuid,'Room 1');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SEC')::uuid,'00000000-0000-0000-0000-0000000000a1','A',1,40);
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
-- ST1 was promoted before section A existed; creating the section placed it automatically (step 8)
SELECT 'ST1 placed by the new section', (SELECT section_id = md5('SEC')::uuid FROM student_sections WHERE student_id = md5('ST1')::uuid) AS in_sec;

-- slip, payment, COR (toggle on). The term was set above (steps 11 and 18).
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
-- actual may be text, boolean or integer: Postgres has no implicit cast of those to text, so it is polymorphic.
CREATE OR REPLACE FUNCTION expect_eq(label text, actual anyelement, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual::text IS NOT DISTINCT FROM expected THEN RAISE NOTICE 'ok   %: %', label, actual;
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
-- the fixture is a late item: remove it so it does not count as an open late item below
DELETE FROM document_requirements WHERE doc_type = 'x_doc';

-- my_open_late_items (20261025060000): a student sees only their own open late items
SELECT act('d1');
SELECT expect_eq('d1 sees Form 137 as open', (SELECT (array_length(my_open_late_items(), 1) = 1 AND (my_open_late_items())[1] LIKE '%Form 137%')::text), 'true');
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

-- ============================================================
-- section scheduling (step 8). Own programs BSY (college 1) and BSZ
-- (college 2). Students are promoted straight into the students table
-- as the Registrar, which runs the same placement trigger as
-- mark_documents_received.
-- ============================================================
SELECT act('ad');
INSERT INTO colleges (id,name,code) VALUES ('00000000-0000-0000-0000-0000000000c2','College of Nursing','CON');
INSERT INTO programs (id,code,name,college_id) VALUES
  ('00000000-0000-0000-0000-0000000000a3','BSY','Test Program Y','00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000a4','BSZ','Test Program Z','00000000-0000-0000-0000-0000000000c2');
INSERT INTO subjects (id,program_id,code,title,units,year_level) VALUES
  (md5('Y1')::uuid,'00000000-0000-0000-0000-0000000000a3','Y101','Y one',3,1),
  (md5('Y2')::uuid,'00000000-0000-0000-0000-0000000000a3','Y102','Y two',3,1),
  (md5('Y3')::uuid,'00000000-0000-0000-0000-0000000000a3','Y201','Y three',3,2),
  (md5('YN')::uuid,'00000000-0000-0000-0000-0000000000a3','Y1XX','Y no year level',3,NULL);
INSERT INTO rooms (id,name,college_id) VALUES (md5('RM1')::uuid,'Room Y1',NULL),(md5('RM2')::uuid,'Room Z1','00000000-0000-0000-0000-0000000000c2');
INSERT INTO auth.users (id,email) VALUES (md5('pf2')::uuid,'pf2@x.ph');
INSERT INTO users (id,auth_id,full_name,email,role) VALUES (md5('pf2')::uuid, md5('pf2')::uuid,'pf2','pf2@x.ph','professor');
SELECT mk_applicant('e1','00000000-0000-0000-0000-0000000000a3', mnl_today());
SELECT mk_applicant('e2','00000000-0000-0000-0000-0000000000a3', mnl_today());
SELECT mk_applicant('e3','00000000-0000-0000-0000-0000000000a3', mnl_today());
SELECT mk_applicant('e4','00000000-0000-0000-0000-0000000000a3', mnl_today());
SELECT mk_applicant('e5','00000000-0000-0000-0000-0000000000a3', mnl_today());
SELECT mk_applicant('z1','00000000-0000-0000-0000-0000000000a4', mnl_today());

-- three students before any section exists: promotion works and nobody is placed
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by)
  SELECT md5('Ae'||n)::uuid,'x',md5('rg')::uuid FROM generate_series(1,3) n;
SELECT expect_eq('promoted with no section: 3 students, 0 placed',
  (SELECT count(*)||'/'||(SELECT count(*) FROM student_sections WHERE student_id IN (SELECT id FROM students WHERE applicant_id IN (md5('Ae1')::uuid,md5('Ae2')::uuid,md5('Ae3')::uuid))) FROM students WHERE applicant_id IN (md5('Ae1')::uuid,md5('Ae2')::uuid,md5('Ae3')::uuid)), '3/0');

-- a new section fills with its subjects (same program and year level only) and takes waiting students up to capacity
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SYA')::uuid,'00000000-0000-0000-0000-0000000000a3','A',1,2);
SELECT expect_eq('new section got the year 1 subjects only',
  (SELECT string_agg(sub.code, ',' ORDER BY sub.code) FROM section_subjects ss JOIN subjects sub ON sub.id = ss.subject_id WHERE ss.section_id = md5('SYA')::uuid), 'Y101,Y102');
SELECT expect_eq('new section placed 2 of 3 waiting (capacity 2)',
  (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SYA')::uuid), '2');
SELECT expect_eq('placed students were told',
  (SELECT count(*)::text FROM notifications WHERE kind = 'section_placed' AND user_id IN (md5('e1')::uuid,md5('e2')::uuid,md5('e3')::uuid)), '2');
SELECT expect_eq('placement notification names the section',
  (SELECT (min(message) LIKE 'You are placed in BSY 1A.%')::text FROM notifications WHERE kind = 'section_placed' AND user_id IN (md5('e1')::uuid,md5('e2')::uuid,md5('e3')::uuid)), 'true');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SYB')::uuid,'00000000-0000-0000-0000-0000000000a3','B',1,1);
SELECT expect_eq('second section took the last waiting student',
  (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SYB')::uuid), '1');
SELECT expect_eq('every section is within capacity',
  (SELECT bool_and(c <= capacity)::text FROM (SELECT s.capacity, count(ss.student_id) c FROM sections s LEFT JOIN student_sections ss ON ss.section_id = s.id WHERE s.program_id = '00000000-0000-0000-0000-0000000000a3' GROUP BY s.id) t), 'true');

-- a student promoted when every seat is taken waits; raising capacity places them
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Ae4')::uuid,'x',md5('rg')::uuid);
SELECT expect_eq('no seat: the new student waits',
  (SELECT count(*)::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid)), '0');
SELECT act('sc');
UPDATE sections SET capacity = 2 WHERE id = md5('SYB')::uuid;
SELECT expect_eq('raising capacity placed the waiting student in B',
  (SELECT section_id::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid)), md5('SYB')::uuid::text);
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Ae5')::uuid,'x',md5('rg')::uuid);
SELECT expect_eq('no seat again: e5 waits',
  (SELECT count(*)::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid)), '0');

-- a subject added later reaches the draft sections of its year level
SELECT act('ad');
INSERT INTO subjects (id,program_id,code,title,units,year_level) VALUES (md5('Y4')::uuid,'00000000-0000-0000-0000-0000000000a3','Y103','Y four',3,1);
SELECT expect_eq('late subject added to both draft sections',
  (SELECT count(*)::text FROM section_subjects WHERE subject_id = md5('Y4')::uuid), '2');

-- loading rules
SELECT act('sc');
SELECT expect_msg('subject of another program', $$INSERT INTO section_subjects (section_id,subject_id) VALUES (md5('SYA')::uuid, md5('SUB')::uuid)$$, 'does not belong');
SELECT expect_msg('room of another college', $$UPDATE section_subjects SET room_id = md5('RM2')::uuid WHERE section_id = md5('SYA')::uuid AND subject_id = md5('Y1')::uuid$$, 'another college');
SELECT expect_msg('assign a non professor', $$UPDATE section_subjects SET professor_id = md5('ap')::uuid WHERE section_id = md5('SYA')::uuid AND subject_id = md5('Y1')::uuid$$, 'not an active Professor');
SELECT expect_msg('submit with nothing assigned', $$UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SYA')::uuid$$, 'still need a professor, room and time');
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=1, start_time='08:00', end_time='09:00' WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y1')::uuid;
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=1, start_time='09:00', end_time='10:00' WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y2')::uuid;
SELECT expect_fail('professor in two places at once', $$UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=NULL, day_of_week=1, start_time='08:30', end_time='09:30' WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y4')::uuid$$);
SELECT expect_fail('room used twice at once, other professor', $$UPDATE section_subjects SET professor_id=md5('pf')::uuid, room_id=md5('RM1')::uuid, day_of_week=1, start_time='08:30', end_time='09:30' WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y4')::uuid$$);
SELECT expect_msg('submit with one subject still open', $$UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SYA')::uuid$$, '1 of 3 subjects');
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=2, start_time='08:00', end_time='09:00' WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y4')::uuid;
SELECT expect_msg('program of a section cannot change', $$UPDATE sections SET program_id = '00000000-0000-0000-0000-0000000000a1' WHERE id = md5('SYA')::uuid$$, 'cannot be changed');
SELECT expect_msg('year level of a section cannot change', $$UPDATE sections SET year_level = 2 WHERE id = md5('SYA')::uuid$$, 'cannot be changed');

-- chain: submit, Dean rejects (reason required), fix, resubmit
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SYA')::uuid;
SELECT expect_eq('submitted', (SELECT schedule_status||'/'||(prepared_by = md5('sc')::uuid)::text FROM sections WHERE id = md5('SYA')::uuid), 'pending_dean/true');
SELECT expect_msg('secretary rejects', $$SELECT reject_schedule(md5('SYA')::uuid, 'no')$$, 'Only the Dean or the Registrar');
SELECT act('rg');
SELECT expect_msg('registrar rejects before the Dean signed', $$SELECT reject_schedule(md5('SYA')::uuid, 'too early')$$, 'Only this college''s Dean can reject');
SELECT act('dn');
SELECT expect_msg('dean rejects without a reason', $$SELECT reject_schedule(md5('SYA')::uuid, '   ')$$, 'reason is required');
SELECT expect_msg('dean rejects by direct update without a reason', $$UPDATE sections SET schedule_status = 'draft' WHERE id = md5('SYA')::uuid$$, 'reason is required');
SELECT reject_schedule(md5('SYA')::uuid, 'Monday loading overlaps with the lab');
SELECT expect_eq('rejected back to draft with the reason stored',
  (SELECT schedule_status||'/'||rejected_reason||'/'||(rejected_by = md5('dn')::uuid)::text FROM sections WHERE id = md5('SYA')::uuid), 'draft/Monday loading overlaps with the lab/true');
SELECT expect_eq('rejection audited with actor and reason',
  (SELECT actor_id::text||'/'||reason FROM audit_log WHERE table_name='sections' AND action='UPDATE' AND record_id = md5('SYA')::uuid::text AND new_data->>'schedule_status'='draft' ORDER BY id DESC LIMIT 1),
  md5('dn')::uuid::text||'/Monday loading overlaps with the lab');
SELECT expect_msg('reject a draft', $$SELECT reject_schedule(md5('SYA')::uuid, 'again')$$, 'Only a schedule waiting');
SELECT act('sc');
UPDATE section_subjects SET day_of_week=3, start_time='08:00', end_time='09:00' WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y4')::uuid;
SELECT expect_eq('loading is open again after rejection', (SELECT day_of_week::text FROM section_subjects WHERE section_id=md5('SYA')::uuid AND subject_id=md5('Y4')::uuid), '3');
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SYA')::uuid;
SELECT expect_eq('resubmit clears the rejection', (SELECT coalesce(rejected_reason,'none')||'/'||coalesce(rejected_by::text,'none') FROM sections WHERE id = md5('SYA')::uuid), 'none/none');
SELECT expect_fail('loading locked while waiting for the Dean', $$UPDATE section_subjects SET room_id = NULL WHERE section_id=md5('SYA')::uuid$$);

-- Dean signs, then the Registrar rejects: back to draft, Dean must sign again
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('SYA')::uuid;
SELECT expect_msg('dean rejects after signing', $$SELECT reject_schedule(md5('SYA')::uuid, 'changed my mind')$$, 'Only the Registrar can reject');
SELECT act('rg');
SELECT reject_schedule(md5('SYA')::uuid, 'Room Y1 is closed on Wednesday');
SELECT expect_eq('registrar rejection: draft, Dean sign-off cleared',
  (SELECT schedule_status||'/'||rejected_reason||'/'||coalesce(dean_signed_by::text,'none')||'/'||(rejected_by = md5('rg')::uuid)::text FROM sections WHERE id = md5('SYA')::uuid),
  'draft/Room Y1 is closed on Wednesday/none/true');
SELECT act('sc'); UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SYA')::uuid;
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('SYA')::uuid;
SELECT expect_msg('dean cannot approve', $$UPDATE sections SET schedule_status = 'approved' WHERE id = md5('SYA')::uuid$$, 'Only the Registrar can approve');
SELECT act('rg'); UPDATE sections SET schedule_status = 'approved' WHERE id = md5('SYA')::uuid;
SELECT expect_eq('approved with both stamps', (SELECT schedule_status||'/'||(dean_signed_by IS NOT NULL)::text||'/'||(approved_by = md5('rg')::uuid)::text FROM sections WHERE id = md5('SYA')::uuid), 'approved/true/true');
SELECT expect_eq('approval told every placed student',
  (SELECT count(*)::text FROM notifications WHERE kind = 'schedule_approved' AND message LIKE 'The schedule for BSY 1A is approved.%'),
  (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SYA')::uuid));
SELECT expect_msg('reject an approved schedule', $$SELECT reject_schedule(md5('SYA')::uuid, 'too late')$$, 'Only a schedule waiting');
SELECT expect_msg('registrar edits capacity', $$UPDATE sections SET capacity = 3 WHERE id = md5('SYA')::uuid$$, 'cannot edit section details');

-- placing and moving students
SELECT act('ad');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES
  (md5('SZA')::uuid,'00000000-0000-0000-0000-0000000000a4','A',1,5),
  (md5('SZB')::uuid,'00000000-0000-0000-0000-0000000000a4','B',1,5);
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Az1')::uuid,'x',md5('rg')::uuid);
SELECT expect_eq('z1 placed automatically in the first section of BSZ',
  (SELECT section_id::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Az1')::uuid)), md5('SZA')::uuid::text);
SELECT expect_msg('registrar moves a student', $$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid), md5('SYA')::uuid)$$, 'Only the College Secretary');
SELECT act('ap');
SELECT expect_msg('applicant calls move', $$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid), md5('SYA')::uuid)$$, 'Only the College Secretary');
SELECT act('fn');
SELECT expect_msg('finance calls reject', $$SELECT reject_schedule(md5('SYA')::uuid, 'x')$$, 'Only the Dean or the Registrar');
SELECT act('sc');
SELECT expect_msg('secretary moves a student of another college', $$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Az1')::uuid), md5('SZB')::uuid)$$, 'another college');
SELECT expect_msg('move to a section of another program', $$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae1')::uuid), md5('SZA')::uuid)$$, 'own program');
SELECT expect_msg('move to the section they are in', $$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid), md5('SYB')::uuid)$$, 'already in this section');
-- e5 waits (no seat): the Secretary places them by hand, over capacity
SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid), md5('SYA')::uuid, 'Seat found for a late arrival');
SELECT expect_eq('manual placement may go over capacity',
  (SELECT count(*)::text||'/'||(SELECT capacity FROM sections WHERE id = md5('SYA')::uuid)::text FROM student_sections WHERE section_id = md5('SYA')::uuid), '3/2');
SELECT expect_eq('manual placement of a waiting student sends section_placed',
  (SELECT count(*)::text FROM notifications WHERE user_id = md5('e5')::uuid AND kind = 'section_placed'), '1');
SELECT expect_eq('manual placement audited with actor and reason',
  (SELECT actor_id::text||'/'||reason FROM audit_log WHERE table_name='student_sections' AND action='INSERT' AND new_data->>'section_id' = md5('SYA')::uuid::text AND new_data->>'student_id' = (SELECT id::text FROM students WHERE applicant_id = md5('Ae5')::uuid)),
  md5('sc')::uuid::text||'/Seat found for a late arrival');
-- move a placed student: allowed, even though both sections are approved or not
SELECT act('dn');
SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid), md5('SYA')::uuid);
SELECT expect_eq('dean moved a student from B to A', (SELECT section_id::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid)), md5('SYA')::uuid::text);
SELECT expect_eq('a move sends section_moved',
  (SELECT count(*)::text FROM notifications WHERE user_id = md5('e4')::uuid AND kind = 'section_moved'), '1');
SELECT expect_eq('the move is audited as an update with the old section',
  (SELECT old_data->>'section_id' FROM audit_log WHERE table_name='student_sections' AND action='UPDATE' AND old_data->>'student_id' = (SELECT id::text FROM students WHERE applicant_id = md5('Ae4')::uuid) ORDER BY id DESC LIMIT 1), md5('SYB')::uuid::text);
SELECT act('ad');
SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid), md5('SYB')::uuid);
SELECT expect_eq('admin moved a student back', (SELECT section_id::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid)), md5('SYB')::uuid::text);
-- once the slip is issued the section is fixed
SELECT act('rg');
INSERT INTO assessment_slips (student_id,payment_required,issued_by) VALUES ((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid),false,md5('rg')::uuid);
SELECT act('sc');
SELECT expect_msg('move after the slip', $$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid), md5('SYB')::uuid)$$, 'assessment slip was already issued');

-- row level security as the signed-in roles (skipped when the role does not exist)
\if :has_auth
SET ROLE authenticated;
SELECT act('sc');
SELECT expect_eq('secretary sees only sections of their own college', (SELECT count(*)::text FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000a4'), '0');
SELECT expect_eq('secretary sees their own sections', ((SELECT count(*) FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000a3') = 2)::text, 'true');
SELECT expect_fail('secretary creates a section in another college', $$INSERT INTO sections (program_id,name,year_level,capacity) VALUES ('00000000-0000-0000-0000-0000000000a4','C',1,5)$$);
SELECT expect_fail('secretary moves a section to the Dean stage directly', $$UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('SYB')::uuid$$);
SELECT act('rg');
SELECT expect_eq('registrar reads professors for the loading', ((SELECT count(*) FROM users WHERE role = 'professor') >= 2)::text, 'true');
SELECT expect_eq('registrar still cannot read staff accounts', (SELECT count(*)::text FROM users WHERE role IN ('dean','college_secretary','finance')), '0');
SELECT expect_fail('registrar creates a section', $$INSERT INTO sections (program_id,name,year_level,capacity) VALUES ('00000000-0000-0000-0000-0000000000a3','C',1,5)$$);
WITH u AS (UPDATE section_subjects SET room_id = NULL WHERE section_id = md5('SYB')::uuid RETURNING 1)
  SELECT expect_eq('registrar edits loading: no row changes', (SELECT count(*)::text FROM u), '0');
SELECT act('e1');
SELECT expect_eq('a student sees only their own section', (SELECT count(*)::text FROM sections), '1');
SELECT expect_fail('a student moves themselves', $$INSERT INTO student_sections (student_id,section_id) VALUES ((SELECT id FROM students WHERE applicant_id = md5('Ae3')::uuid), md5('SYB')::uuid)$$);
SELECT act('pf2');
SELECT expect_eq('professor sees their sections', ((SELECT count(*) FROM sections) >= 1)::text, 'true');
SELECT expect_eq('professor class list has names and numbers only', (SELECT count(*)::text FROM professor_class_lists WHERE section_id = md5('SYA')::uuid AND student_number IS NOT NULL AND full_name IS NOT NULL), '9');
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 8 row level security checks not run';
\endif

-- ============================================================
-- assessment slip (step 9). Uses the step 8 fixtures: section SYA is
-- approved with students, SYB is still a draft, e5 already has a slip.
-- ============================================================
CREATE TEMP TABLE slipsnap AS
  SELECT count(*)::text AS ready FROM student_sections ss JOIN sections s ON s.id = ss.section_id
   WHERE s.schedule_status = 'approved' AND NOT EXISTS (SELECT 1 FROM assessment_slips sl WHERE sl.student_id = ss.student_id);
SELECT act('sc');
SELECT expect_msg('secretary issues a slip', $$SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid))$$, 'Only the Registrar or Admin');
SELECT expect_msg('secretary issues all', $$SELECT issue_all_ready_slips()$$, 'Only the Registrar or Admin');
SELECT act('rg');
SELECT expect_msg('slip while the schedule is a draft', $$SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid))$$, 'must be approved');
SELECT expect_msg('slip for nobody', $$SELECT issue_assessment_slip(md5('nobody')::uuid)$$, 'Student not found');
SELECT expect_msg('slip issued twice', $$SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid))$$, 'already issued');
SELECT expect_eq('issue all ready returns the number waiting', (SELECT issued::text FROM issue_all_ready_slips()), (SELECT ready FROM slipsnap));
SELECT expect_eq('nobody in an approved section is left without a slip',
  (SELECT count(*)::text FROM student_sections ss JOIN sections s ON s.id = ss.section_id
    WHERE s.schedule_status = 'approved' AND NOT EXISTS (SELECT 1 FROM assessment_slips sl WHERE sl.student_id = ss.student_id)), '0');
SELECT expect_eq('issue all again does nothing', (SELECT issued::text FROM issue_all_ready_slips()), '0');
SELECT expect_eq('each issued slip told its student once',
  (SELECT count(*)::text FROM notifications WHERE kind = 'slip_issued'), (SELECT ready FROM slipsnap));
SELECT expect_eq('no payment required: the notification points to the COR',
  (SELECT (min(message) LIKE '%the Registrar issues your COR.')::text FROM notifications WHERE kind = 'slip_issued' AND user_id IN (md5('e1')::uuid, md5('e2')::uuid, md5('e3')::uuid)), 'true');
SELECT expect_eq('issued slips are audited with the registrar',
  (SELECT count(DISTINCT actor_id)::text||'/'||min(actor_id::text) FROM audit_log WHERE table_name = 'assessment_slips' AND action = 'INSERT' AND new_data->>'student_id' IN (SELECT id::text FROM students WHERE applicant_id IN (md5('Ae1')::uuid, md5('Ae2')::uuid, md5('Ae3')::uuid))),
  '1/'||md5('rg')::uuid::text);

-- what the slip shows, and who may read it
SELECT expect_eq('registrar reads a slip: number, section and 3 subjects',
  (SELECT (s->>'studentNumber' IS NOT NULL)::text||'/'||(s->>'section')||'/'||jsonb_array_length(s->'subjects')::text
     FROM (SELECT assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid)) s) t),
  'true/BSY 1A/3');
SELECT expect_eq('slip subjects carry professor, room and time',
  (SELECT (sub->>'professor' = 'pf2' AND sub->>'room' = 'Room Y1' AND sub->>'start' IS NOT NULL)::text
     FROM (SELECT jsonb_array_elements(assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid))->'subjects') sub LIMIT 1) t), 'true');
SELECT expect_eq('slip without an issue is null', coalesce(assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid))::text, 'null'), 'null');
SELECT act('e5');
SELECT expect_eq('a student reads their own slip', (assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae5')::uuid)) IS NOT NULL)::text, 'true');
SELECT expect_msg('a student reads another slip', $$SELECT assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae1')::uuid))$$, 'only view your own');
SELECT act('fn');
SELECT expect_msg('finance reads a slip', $$SELECT assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae1')::uuid))$$, 'only view your own');
SELECT act('ap2');
SELECT expect_msg('an applicant reads a slip', $$SELECT assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ae1')::uuid))$$, 'only view your own');

-- ============================================================
-- laboratory meetings. Own program BSW (college 1).
-- ============================================================
SELECT act('ad');
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000a5','BSW','Test Program W','00000000-0000-0000-0000-0000000000c1');
INSERT INTO subjects (id,program_id,code,title,units,year_level,has_laboratory) VALUES
  (md5('W1')::uuid,'00000000-0000-0000-0000-0000000000a5','W101','W one',3,1,true),
  (md5('W2')::uuid,'00000000-0000-0000-0000-0000000000a5','W102','W two',3,1,false);
SELECT mk_applicant('w1','00000000-0000-0000-0000-0000000000a5', mnl_today());
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SWA')::uuid,'00000000-0000-0000-0000-0000000000a5','A',1,5);
SELECT expect_eq('lecture row per subject, laboratory row only where flagged',
  (SELECT string_agg(sub.code||':'||ss.meeting, ',' ORDER BY sub.code, ss.meeting DESC) FROM section_subjects ss JOIN subjects sub ON sub.id = ss.subject_id WHERE ss.section_id = md5('SWA')::uuid),
  'W101:lecture,W101:laboratory,W102:lecture');
SELECT expect_fail('second lecture row for the same subject', $$INSERT INTO section_subjects (section_id,subject_id,meeting) VALUES (md5('SWA')::uuid, md5('W1')::uuid, 'lecture')$$);
SELECT expect_fail('unknown meeting type', $$INSERT INTO section_subjects (section_id,subject_id,meeting) VALUES (md5('SWA')::uuid, md5('W2')::uuid, 'seminar')$$);
SELECT act('ad');
UPDATE subjects SET has_laboratory = true WHERE id = md5('W2')::uuid;
SELECT expect_eq('flagging a subject later adds its laboratory row once',
  (SELECT count(*)::text FROM section_subjects WHERE section_id = md5('SWA')::uuid AND subject_id = md5('W2')::uuid), '2');
UPDATE subjects SET has_laboratory = false WHERE id = md5('W2')::uuid;
UPDATE subjects SET has_laboratory = true WHERE id = md5('W2')::uuid;
SELECT expect_eq('flagging again adds nothing', (SELECT count(*)::text FROM section_subjects WHERE section_id = md5('SWA')::uuid), '4');

-- lecture and laboratory of one subject: own room, day and time, same professor
SELECT act('sc');
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=4, start_time='08:00', end_time='09:00' WHERE section_id=md5('SWA')::uuid AND subject_id=md5('W1')::uuid AND meeting='lecture';
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=4, start_time='09:00', end_time='11:00' WHERE section_id=md5('SWA')::uuid AND subject_id=md5('W1')::uuid AND meeting='laboratory';
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=5, start_time='08:00', end_time='09:00' WHERE section_id=md5('SWA')::uuid AND subject_id=md5('W2')::uuid AND meeting='lecture';
SELECT expect_msg('laboratory row still open blocks the submit', $$UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SWA')::uuid$$, '1 of 4 subjects');
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=5, start_time='09:00', end_time='10:00' WHERE section_id=md5('SWA')::uuid AND subject_id=md5('W2')::uuid AND meeting='laboratory';
SELECT expect_fail('laboratory overlapping its own lecture', $$UPDATE section_subjects SET day_of_week=4, start_time='08:30', end_time='09:30' WHERE section_id=md5('SWA')::uuid AND subject_id=md5('W1')::uuid AND meeting='laboratory'$$);
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SWA')::uuid;
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('SWA')::uuid;
SELECT act('rg'); UPDATE sections SET schedule_status = 'approved' WHERE id = md5('SWA')::uuid;
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Aw1')::uuid,'x',md5('rg')::uuid);
SELECT expect_eq('w1 placed in the new section', (SELECT section_id::text FROM student_sections WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Aw1')::uuid)), md5('SWA')::uuid::text);
SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Aw1')::uuid));
SELECT expect_eq('slip lists lecture and laboratory rows', (SELECT jsonb_array_length(assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Aw1')::uuid))->'subjects')::text), '4');
SELECT expect_eq('slip units count once: 6 in total, laboratory rows 0',
  (SELECT (sum((e->>'units')::numeric) = 6)::text||'/'||count(*) FILTER (WHERE e->>'meeting' = 'laboratory' AND (e->>'units')::numeric = 0)::text
     FROM jsonb_array_elements(assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Aw1')::uuid))->'subjects') e), 'true/2');

-- ============================================================
-- payment (step 10), 20261025100000_payment.sql. Own program BSV with the
-- toggle on: three students get a slip and so a pending payment.
-- ============================================================
SELECT act('ad');
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000a6','BSV','Test Program V','00000000-0000-0000-0000-0000000000c1');
INSERT INTO subjects (id,program_id,code,title,units,year_level) VALUES (md5('V1')::uuid,'00000000-0000-0000-0000-0000000000a6','V101','V one',3,1);
SELECT mk_applicant('v1','00000000-0000-0000-0000-0000000000a6', mnl_today());
SELECT mk_applicant('v2','00000000-0000-0000-0000-0000000000a6', mnl_today());
SELECT mk_applicant('v3','00000000-0000-0000-0000-0000000000a6', mnl_today());
UPDATE program_payment_settings SET payment_required = true WHERE program_id = '00000000-0000-0000-0000-0000000000a6';
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SVA')::uuid,'00000000-0000-0000-0000-0000000000a6','A',1,10);
UPDATE section_subjects SET professor_id=md5('pf2')::uuid, room_id=md5('RM1')::uuid, day_of_week=2, start_time='08:00', end_time='09:00' WHERE section_id=md5('SVA')::uuid;
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SVA')::uuid;
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('SVA')::uuid;
SELECT act('rg'); UPDATE sections SET schedule_status = 'approved' WHERE id = md5('SVA')::uuid;
INSERT INTO students (applicant_id,student_number,documents_received_by) SELECT md5('Av'||n)::uuid,'x',md5('rg')::uuid FROM generate_series(1,3) n;
SELECT expect_eq('three slips issued with payment required', (SELECT issued::text FROM issue_all_ready_slips() WHERE EXISTS (SELECT 1)), '3');
SELECT expect_eq('each slip opened a pending payment', (SELECT count(*)::text FROM payments WHERE status = 'pending' AND student_id IN (SELECT id FROM students WHERE applicant_id IN (md5('Av1')::uuid, md5('Av2')::uuid, md5('Av3')::uuid))), '3');

-- who may call them: Finance and Admin only
SELECT act('rg');
SELECT expect_msg('registrar records a payment', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 1000, 'OR-1')$$, 'Only Finance or Admin');
SELECT expect_msg('registrar reads the queue', $$SELECT * FROM payment_queue('pending')$$, 'Only Finance or Admin');
SELECT act('ap2'); SELECT expect_msg('applicant records a payment', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 1000, 'OR-1')$$, 'Only Finance or Admin');
SELECT act('sc'); SELECT expect_msg('secretary records a payment', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 1000, 'OR-1')$$, 'Only Finance or Admin');

-- input rules, then clearing
SELECT act('fn');
SELECT expect_eq('pending queue lists the three, lowest number first',
  (SELECT count(*)::text||'/'||bool_and(program_code = 'BSV')::text FROM payment_queue('pending') WHERE student_number IN (SELECT student_number FROM students WHERE applicant_id IN (md5('Av1')::uuid, md5('Av2')::uuid, md5('Av3')::uuid))), '3/true');
SELECT expect_msg('partial payment', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 999.99, 'OR-1')$$, 'must cover the amount due');
SELECT expect_msg('negative amount due', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), -1, 0, NULL)$$, 'Enter the amount due');
SELECT expect_msg('paid without a receipt', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 1000, '  ')$$, 'receipt number');
SELECT expect_msg('payment for a student with none', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Ae1')::uuid), 1000, 1000, 'OR-1')$$, 'no payment to record');
SELECT expect_eq('refusals left everything pending', (SELECT count(*)::text FROM payments WHERE status = 'pending' AND student_id IN (SELECT id FROM students WHERE applicant_id IN (md5('Av1')::uuid, md5('Av2')::uuid, md5('Av3')::uuid))), '3');
SELECT act('rg');
SELECT expect_msg('COR before payment is cleared', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'Payment must be cleared');
SELECT act('fn');
SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 1500.50, ' OR-1 ');
SELECT expect_eq('cleared payment keeps amounts, trimmed receipt and the actor',
  (SELECT amount_due::text||'/'||amount_paid::text||'/'||receipt_no||'/'||status||'/'||(recorded_by = md5('fn')::uuid)::text FROM payments WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)),
  '1000.00/1500.50/OR-1/cleared/true');
SELECT expect_eq('student was told once', (SELECT count(*)::text FROM notifications WHERE kind = 'payment_cleared' AND user_id = md5('v1')::uuid), '1');
SELECT expect_msg('record the same payment again', $$SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid), 1000, 1000, 'OR-2')$$, 'already recorded');
SELECT expect_fail('edit a cleared payment', $$UPDATE payments SET amount_paid = 5 WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)$$);
SELECT expect_eq('cleared queue has the cleared one', (SELECT count(*)::text FROM payment_queue('cleared') WHERE student_number = (SELECT student_number FROM students WHERE applicant_id = md5('Av1')::uuid)), '1');
SELECT expect_msg('unknown queue status', $$SELECT * FROM payment_queue('paid')$$, 'Unknown payment status');
-- zero due, zero paid, no receipt: clears (a fully waived fee)
SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av2')::uuid), 0, 0, NULL);
SELECT expect_eq('a zero payment clears without a receipt', (SELECT status||'/'||coalesce(receipt_no,'none') FROM payments WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av2')::uuid)), 'cleared/none');
-- Admin may record too
SELECT act('ad');
SELECT record_payment((SELECT id FROM students WHERE applicant_id = md5('Av3')::uuid), 500, 500, 'OR-3');
SELECT expect_eq('admin recorded a payment', (SELECT (recorded_by = md5('ad')::uuid)::text FROM payments WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av3')::uuid)), 'true');

-- my_payment_status: a student sees only their own state
SELECT act('v1'); SELECT expect_eq('v1 payment is cleared', my_payment_status(), 'cleared');
SELECT act('e1'); SELECT expect_eq('a student with no payment gets null', coalesce(my_payment_status(), 'null'), 'null');
SELECT act('fn'); SELECT expect_eq('finance gets null', coalesce(my_payment_status(), 'null'), 'null');

-- the toggle: Finance changes it, the change is audited, old slips keep their snapshot
SELECT act('fn');
UPDATE program_payment_settings SET payment_required = false WHERE program_id = '00000000-0000-0000-0000-0000000000a6';
SELECT expect_eq('toggle change audited with the finance actor',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'program_payment_settings' AND actor_id = md5('fn')::uuid AND new_data->>'program_id' = '00000000-0000-0000-0000-0000000000a6' AND new_data->>'payment_required' = 'false'), '1');
SELECT expect_eq('issued slips keep the snapshot', (SELECT bool_and(sl.payment_required)::text FROM assessment_slips sl JOIN students st ON st.id = sl.student_id WHERE st.applicant_id IN (md5('Av1')::uuid, md5('Av2')::uuid, md5('Av3')::uuid)), 'true');

-- payment row level security as the signed-in roles
\if :has_auth
SET ROLE authenticated;
SELECT act('v1');
SELECT expect_eq('a student cannot read payments', (SELECT count(*)::text FROM payments), '0');
SELECT act('rg');
DO $$ DECLARE n integer; BEGIN
  UPDATE program_payment_settings SET payment_required = NOT payment_required WHERE program_id = '00000000-0000-0000-0000-0000000000a6';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE NOTICE 'ok   blocked: registrar changes the toggle -> row level security hides the row';
  ELSE RAISE NOTICE 'FAIL (should not change): registrar changes the toggle'; END IF;
END $$;
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 10 row level security checks not run';
\endif

-- ============================================================
-- COR (step 11), 20261025110000_cor.sql. Uses the step 10 students: v1 and
-- v2 paid, v3 paid too; the toggle is off again, so a new student needs none.
-- ============================================================
-- the term: Admin only, shape checked, one row
SELECT act('ad');
SELECT expect_fail('term with non consecutive years', $$UPDATE enrollment_term SET school_year = '2026-2028'$$);
SELECT expect_fail('term with a bad format', $$UPDATE enrollment_term SET school_year = '26-27'$$);
SELECT expect_fail('unknown semester', $$UPDATE enrollment_term SET semester = '3rd'$$);
SELECT expect_fail('second term row', $$INSERT INTO enrollment_term (id, school_year, semester) VALUES (false, '2027-2028', '2nd')$$);
SELECT expect_eq('term row stamped with the actor', (SELECT (updated_by = md5('ad')::uuid)::text FROM enrollment_term), 'true');
\if :has_auth
SET ROLE authenticated;
SELECT act('rg');
SELECT expect_eq('registrar cannot read the term', (SELECT count(*)::text FROM enrollment_term), '0');
DO $$ DECLARE n integer; BEGIN
  UPDATE enrollment_term SET semester = '2nd';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE NOTICE 'ok   blocked: registrar sets the term -> row level security hides the row';
  ELSE RAISE NOTICE 'FAIL (should not change): registrar sets the term'; END IF;
END $$;
SELECT act('ad');
UPDATE enrollment_term SET semester = '2nd';
SELECT expect_eq('admin changes the term, audited', (SELECT count(*)::text FROM audit_log WHERE table_name = 'enrollment_term' AND action = 'UPDATE' AND new_data->>'semester' = '2nd'), '1');
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 11 row level security checks not run';
\endif
SELECT act('ad'); UPDATE enrollment_term SET semester = '1st';

-- who may call them: Registrar and Admin only
SELECT act('fn');
SELECT expect_msg('finance issues a COR', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'Only the Registrar or Admin');
SELECT expect_msg('finance issues all', $$SELECT issue_all_ready_cors()$$, 'Only the Registrar or Admin');
SELECT act('sc'); SELECT expect_msg('secretary issues a COR', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'Only the Registrar or Admin');
SELECT act('ap2'); SELECT expect_msg('applicant issues a COR', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'Only the Registrar or Admin');

-- the order is enforced
SELECT act('rg');
SELECT expect_msg('COR for nobody', $$SELECT issue_cor(md5('nobody')::uuid)$$, 'Student not found');
SELECT expect_msg('COR before the slip', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid))$$, 'assessment slip must be issued');

-- no term, no COR (the term row is taken away for one check, as superuser)
SELECT act('ad'); DELETE FROM enrollment_term;
SELECT act('rg');
SELECT expect_msg('COR without a term', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'not set');
SELECT expect_eq('the refusal left no COR', (SELECT count(*)::text FROM cors WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)), '0');
SELECT act('ad'); INSERT INTO enrollment_term (school_year, semester) VALUES ('2026-2027','1st');

-- issue one: stamped with the term, the actor and a notification
SELECT act('rg');
SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid));
SELECT expect_eq('COR carries the term and the registrar',
  (SELECT school_year||'/'||semester||'/'||(issued_by = md5('rg')::uuid)::text FROM cors WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)), '2026-2027/1st/true');
SELECT expect_eq('student told once, with the term',
  (SELECT count(*)::text||'/'||(min(message) LIKE '%1st semester%2026-2027%')::text FROM notifications WHERE kind = 'cor_issued' AND user_id = md5('v1')::uuid), '1/true');
SELECT expect_msg('COR issued twice', $$SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'already issued');

-- an old COR keeps its term when the term changes
SELECT act('ad'); UPDATE enrollment_term SET semester = '2nd';
SELECT expect_eq('old COR keeps the 1st semester', (SELECT semester FROM cors WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)), '1st');

-- issue all ready: v2 and v3 are paid, with the new term; e1 to e3 have a slip and no payment required
SELECT act('rg');
SELECT expect_eq('issue all issued at least v2 and v3', ((SELECT issued FROM issue_all_ready_cors()) >= 2)::text, 'true');
SELECT expect_eq('nobody ready is left without a COR',
  (SELECT count(*)::text FROM assessment_slips sl WHERE NOT EXISTS (SELECT 1 FROM cors c WHERE c.student_id = sl.student_id)
     AND (NOT sl.payment_required OR EXISTS (SELECT 1 FROM payments p WHERE p.student_id = sl.student_id AND p.status = 'cleared'))), '0');
SELECT expect_eq('issue all again does nothing', (SELECT issued::text FROM issue_all_ready_cors()), '0');
-- Changed in step 18: a COR carries the term of the enrollment it belongs to. v2 enrolled in the 1st
-- semester, so the COR says 1st even though the term is now the 2nd. It used to say 2nd.
SELECT expect_eq('v2 COR carries the term of v2 enrollment', (SELECT semester FROM cors WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Av2')::uuid)), '1st');

-- what the COR shows, and who may read it
SELECT expect_eq('registrar reads a COR: term, section, 1 subject, payment shown',
  (SELECT (c->>'schoolYear')||'/'||(c->>'semester')||'/'||(c->>'section')||'/'||jsonb_array_length(c->'subjects')::text||'/'||(c->>'amountPaid')||'/'||(c->>'receiptNo')||'/'||(c->>'collegeName')
     FROM (SELECT certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)) c) t),
  '2026-2027/1st/BSV 1A/1/1500.50/OR-1/College of Ed');
SELECT expect_eq('COR names the issuer and the student type',
  (SELECT (c->>'issuedByName')||'/'||(c->>'issuedByRole')||'/'||(c->>'admissionType')||'/'||(c->>'yearLevel')
     FROM (SELECT certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)) c) t), 'rg/registrar/new/1');
SELECT expect_eq('COR without an issue is null', coalesce(certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Ae4')::uuid))::text, 'null'), 'null');
SELECT act('v1');
SELECT expect_eq('a student reads their own COR', (certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid)) IS NOT NULL)::text, 'true');
SELECT expect_msg('a student reads another COR', $$SELECT certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Av2')::uuid))$$, 'only view your own');
SELECT act('fn');
SELECT expect_msg('finance reads a COR', $$SELECT certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'only view your own');
SELECT act('ap2');
SELECT expect_msg('an applicant reads a COR', $$SELECT certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Av1')::uuid))$$, 'only view your own');

-- ============================================================
-- reschedules (step 12), 20261025120000_reschedules.sql. Own programs BSR
-- (mass reschedule) and BSQ (requests) on dates 40 to 47 days out, so earlier
-- fixtures cannot change the order. A reschedule moves the visit only: the
-- student count is compared at the end.
-- ============================================================
CREATE TEMP TABLE snap12 AS SELECT count(*)::text AS students FROM students;
CREATE OR REPLACE FUNCTION req_id(k text, st text) RETURNS uuid LANGUAGE sql AS $$
  SELECT rr.id FROM reschedule_requests rr JOIN visit_bookings b ON b.id = rr.booking_id
   WHERE b.applicant_id = md5('A'||k)::uuid AND rr.status = st ORDER BY rr.created_at DESC LIMIT 1
$$;

SELECT act('ad');
INSERT INTO programs (id,code,name,college_id) VALUES
  ('00000000-0000-0000-0000-0000000000a7','BSR','Test Program R','00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000a8','BSQ','Test Program Q','00000000-0000-0000-0000-0000000000c1');
-- r1 to r6 in BSR, admitted oldest first. q1 to q5 in BSQ.
SELECT mk_applicant('r1','00000000-0000-0000-0000-0000000000a7', mnl_today()-5);
SELECT mk_applicant('r2','00000000-0000-0000-0000-0000000000a7', mnl_today()-4);
SELECT mk_applicant('r3','00000000-0000-0000-0000-0000000000a7', mnl_today()-3);
SELECT mk_applicant('r4','00000000-0000-0000-0000-0000000000a7', mnl_today()-2);
SELECT mk_applicant('r5','00000000-0000-0000-0000-0000000000a7', mnl_today()-1);
SELECT mk_applicant('r6','00000000-0000-0000-0000-0000000000a7', mnl_today()-1);
SELECT mk_applicant('q1','00000000-0000-0000-0000-0000000000a8', mnl_today()-5);
SELECT mk_applicant('q2','00000000-0000-0000-0000-0000000000a8', mnl_today()-4);
SELECT mk_applicant('q3','00000000-0000-0000-0000-0000000000a8', mnl_today()-3);
SELECT mk_applicant('q4','00000000-0000-0000-0000-0000000000a8', mnl_today()-2);
SELECT mk_applicant('q5','00000000-0000-0000-0000-0000000000a8', mnl_today()-1);

-- BSR: the affected date is +40. SR1 and SR2 are full once r1 to r4 are in; SRD still has seats.
SELECT act('rg');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring,status) VALUES
  (md5('SR1')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+40,'09:00','10:00',2,'Registrar Office','x','open'),
  (md5('SR2')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+40,'10:00','11:00',2,'Cashier','x','open'),
  (md5('SRD')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+40,'11:00','12:00',5,'Registrar Office','x','open'),
  (md5('SR3')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+41,'09:00','10:00',1,'Registrar Office','x','open'),
  (md5('SR4')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+41,'10:00','11:00',1,'Registrar Office','x','open'),
  (md5('SRC')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+42,'08:00','09:00',5,'Registrar Office','x','closed');
INSERT INTO visit_bookings (applicant_id,slot_id) VALUES
  (md5('Ar1')::uuid, md5('SR1')::uuid), (md5('Ar2')::uuid, md5('SR1')::uuid),
  (md5('Ar3')::uuid, md5('SR2')::uuid), (md5('Ar4')::uuid, md5('SR2')::uuid);
-- an attended and a no show visit on the same date: a reschedule never moves them
INSERT INTO visit_bookings (applicant_id,slot_id,status) VALUES
  (md5('Ar5')::uuid, md5('SRD')::uuid, 'attended'), (md5('Ar6')::uuid, md5('SRD')::uuid, 'no_show');

-- next_open_slot with the two optional arguments (the one argument call is checked in step 6)
SELECT expect_eq('next open slot, no exclusion, is the seat on the busy date', next_open_slot('00000000-0000-0000-0000-0000000000a7')::text, md5('SRD')::uuid::text);
SELECT expect_eq('next open slot skips the excluded date', next_open_slot('00000000-0000-0000-0000-0000000000a7', mnl_today()+40)::text, md5('SR3')::uuid::text);
SELECT expect_eq('excluding one office keeps the other offices on that date',
  next_open_slot('00000000-0000-0000-0000-0000000000a7', mnl_today()+40, 'Cashier')::text, md5('SRD')::uuid::text);
SELECT expect_eq('excluding an office that is not on the date excludes nothing',
  next_open_slot('00000000-0000-0000-0000-0000000000a7', mnl_today()+40, 'Elsewhere')::text, md5('SRD')::uuid::text);

-- who may set a mass reschedule: Registrar and Admin only
SELECT act('ap2'); SELECT expect_msg('applicant sets a mass reschedule', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, 'x')$$, 'Only the Registrar or Admin');
SELECT act('ap');  SELECT expect_msg('student sets a mass reschedule', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, 'x')$$, 'Only the Registrar or Admin');
SELECT act('fn');  SELECT expect_msg('finance sets a mass reschedule', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, 'x')$$, 'Only the Registrar or Admin');
SELECT act('sc');  SELECT expect_msg('secretary sets a mass reschedule', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, 'x')$$, 'Only the Registrar or Admin');
SELECT act('dn');  SELECT expect_msg('dean sets a mass reschedule', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, 'x')$$, 'Only the Registrar or Admin');
SELECT act('pf');  SELECT expect_msg('professor sets a mass reschedule', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, 'x')$$, 'Only the Registrar or Admin');

-- input refusals leave no record and move nobody
SELECT act('rg');
SELECT expect_msg('mass reschedule without a date', $$SELECT mass_reschedule(NULL, NULL, NULL, 'x')$$, 'Choose the affected date');
SELECT expect_msg('mass reschedule for a past date', $$SELECT mass_reschedule(mnl_today()-1, NULL, NULL, 'x')$$, 'cannot be in the past');
SELECT expect_msg('mass reschedule without a reason', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, '   ')$$, 'Enter the reason');
SELECT expect_msg('mass reschedule with a 501 character reason', $$SELECT mass_reschedule(mnl_today()+40, NULL, NULL, repeat('x', 501))$$, 'longer than 500');
SELECT expect_msg('mass reschedule on a date with no booked visit', $$SELECT mass_reschedule(mnl_today()+20, NULL, NULL, 'x')$$, 'No booked visit falls on that date');
SELECT expect_msg('mass reschedule for a program with nobody that day', $$SELECT mass_reschedule(mnl_today()+40, '00000000-0000-0000-0000-0000000000a1', NULL, 'x')$$, 'No booked visit falls on that date');
SELECT expect_msg('mass reschedule for an office with nobody that day', $$SELECT mass_reschedule(mnl_today()+40, NULL, 'Elsewhere', 'x')$$, 'No booked visit falls on that date');
SELECT expect_eq('refusals left no record and moved nobody',
  (SELECT count(*)::text FROM mass_reschedules WHERE affected_date = mnl_today()+40)||'/'||
  (SELECT count(*)::text FROM visit_bookings WHERE slot_id IN (md5('SR1')::uuid, md5('SR2')::uuid)), '0/4');

-- run 1: one office. r3 and r4 (Cashier) go to the seat at the other office on the same date; r1 and r2 stay.
SELECT expect_eq('office run: moved / left over',
  (SELECT moved||'/'||left_over FROM mass_reschedule(mnl_today()+40, '00000000-0000-0000-0000-0000000000a7', 'Cashier', 'typhoon')), '2/0');
SELECT expect_eq('office run: r3 and r4 are in SRD, r1 and r2 stay in SR1',
  (SELECT count(*)::text FROM visit_bookings WHERE applicant_id IN (md5('Ar3')::uuid, md5('Ar4')::uuid) AND slot_id = md5('SRD')::uuid)||'/'||
  (SELECT count(*)::text FROM visit_bookings WHERE applicant_id IN (md5('Ar1')::uuid, md5('Ar2')::uuid) AND slot_id = md5('SR1')::uuid), '2/2');
SELECT expect_eq('office run: the event is recorded with its filters, the actor and no target slot',
  (SELECT office_name||'/'||reason||'/'||(program_id = '00000000-0000-0000-0000-0000000000a7')::text||'/'||(triggered_by = md5('rg')::uuid)::text||'/'||(target_slot_id IS NULL)::text
     FROM mass_reschedules WHERE affected_date = mnl_today()+40), 'Cashier/typhoon/true/true/true');
SELECT expect_eq('office run: r3 was told once, email pending',
  (SELECT count(*)::text||'/'||min(email_status) FROM notifications WHERE user_id = md5('r3')::uuid AND kind = 'visit_moved'), '1/pending');
SELECT expect_eq('office run: audit has the reason and the registrar',
  (SELECT reason||'/'||(actor_id = md5('rg')::uuid)::text FROM audit_log
    WHERE table_name = 'visit_bookings' AND action = 'UPDATE' AND new_data->>'applicant_id' = md5('Ar3')::uuid::text AND new_data->>'slot_id' = md5('SRD')::uuid::text),
  'Mass reschedule: typhoon/true');
SELECT expect_eq('office run: r1 and r2 were not told', (SELECT count(*)::text FROM notifications WHERE user_id IN (md5('r1')::uuid, md5('r2')::uuid)), '0');

-- run 2: the whole date, by Admin. The emptied date is never chosen, so r3 and r4 (now in SRD on that date) do not fit and stay.
SELECT act('ad');
SELECT expect_eq('date run: moved / left over',
  (SELECT moved||'/'||left_over FROM mass_reschedule(mnl_today()+40, '00000000-0000-0000-0000-0000000000a7', NULL, 'closure')), '2/2');
SELECT expect_eq('date run: admission order, r1 in SR3 and r2 in SR4',
  (SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Ar1')::uuid)||'/'||(SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Ar2')::uuid),
  md5('SR3')::uuid::text||'/'||md5('SR4')::uuid::text);
SELECT expect_eq('date run: the free seat on the emptied date was not used, r3 and r4 stay',
  (SELECT count(*)::text FROM visit_bookings WHERE applicant_id IN (md5('Ar3')::uuid, md5('Ar4')::uuid) AND slot_id = md5('SRD')::uuid), '2');
SELECT expect_eq('date run: attended and no show stay as they are',
  (SELECT status FROM visit_bookings WHERE applicant_id = md5('Ar5')::uuid)||'/'||(SELECT status FROM visit_bookings WHERE applicant_id = md5('Ar6')::uuid)||'/'||
  (SELECT count(*)::text FROM visit_bookings WHERE applicant_id IN (md5('Ar5')::uuid, md5('Ar6')::uuid) AND slot_id = md5('SRD')::uuid), 'attended/no_show/2');
SELECT expect_eq('date run: audit has the reason and the admin',
  (SELECT reason||'/'||(actor_id = md5('ad')::uuid)::text FROM audit_log
    WHERE table_name = 'visit_bookings' AND action = 'UPDATE' AND new_data->>'applicant_id' = md5('Ar1')::uuid::text AND new_data->>'slot_id' = md5('SR3')::uuid::text),
  'Mass reschedule: closure/true');
SELECT expect_eq('date run: the event is audited with the admin',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'mass_reschedules' AND action = 'INSERT' AND actor_id = md5('ad')::uuid AND new_data->>'reason' = 'closure'), '1');
SELECT expect_eq('every BSR slot is within capacity',
  (SELECT bool_and(c <= capacity)::text FROM (SELECT s.capacity, count(b.id) c FROM visit_slots s LEFT JOIN visit_bookings b ON b.slot_id = s.id
     WHERE s.program_id = '00000000-0000-0000-0000-0000000000a7' GROUP BY s.id, s.capacity) t), 'true');

-- run 3: after the Registrar adds a slot, running it again moves the two who stayed
SELECT act('rg');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring,status)
  VALUES (md5('SRG')::uuid,'00000000-0000-0000-0000-0000000000a7',mnl_today()+42,'09:00','10:00',5,'Registrar Office','x','open');
SELECT expect_eq('run again: moved / left over',
  (SELECT moved||'/'||left_over FROM mass_reschedule(mnl_today()+40, '00000000-0000-0000-0000-0000000000a7', NULL, 'closure, second run')), '2/0');
SELECT expect_eq('run again: r3 and r4 are in the new slot',
  (SELECT count(*)::text FROM visit_bookings WHERE applicant_id IN (md5('Ar3')::uuid, md5('Ar4')::uuid) AND slot_id = md5('SRG')::uuid), '2');
SELECT expect_msg('run again with nobody booked on the date', $$SELECT mass_reschedule(mnl_today()+40, '00000000-0000-0000-0000-0000000000a7', NULL, 'x')$$, 'No booked visit falls on that date');
SELECT expect_eq('three runs, three records', (SELECT count(*)::text FROM mass_reschedules WHERE affected_date = mnl_today()+40), '3');

-- BSQ: q1 to q3 booked in QF1 (+45). QF2 and QF3 hold one seat each. QC is closed.
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring,status) VALUES
  (md5('QF1')::uuid,'00000000-0000-0000-0000-0000000000a8',mnl_today()+45,'09:00','10:00',5,'Registrar Office','x','open'),
  (md5('QF2')::uuid,'00000000-0000-0000-0000-0000000000a8',mnl_today()+46,'09:00','10:00',1,'Registrar Office','x','open'),
  (md5('QF3')::uuid,'00000000-0000-0000-0000-0000000000a8',mnl_today()+47,'09:00','10:00',1,'Registrar Office','x','open'),
  (md5('QC')::uuid, '00000000-0000-0000-0000-0000000000a8',mnl_today()+44,'09:00','10:00',5,'Registrar Office','x','closed');
INSERT INTO visit_bookings (applicant_id,slot_id) VALUES
  (md5('Aq1')::uuid, md5('QF1')::uuid), (md5('Aq2')::uuid, md5('QF1')::uuid), (md5('Aq3')::uuid, md5('QF1')::uuid);
INSERT INTO visit_bookings (applicant_id,slot_id,status) VALUES (md5('Aq5')::uuid, md5('QF1')::uuid, 'attended');

-- who may ask: applicants and students only, with a booked visit and a reason
SELECT act('rg'); SELECT expect_msg('registrar requests a reschedule', $$SELECT request_reschedule('x')$$, 'Only an applicant or student');
SELECT act('fn'); SELECT expect_msg('finance requests a reschedule', $$SELECT request_reschedule('x')$$, 'Only an applicant or student');
SELECT act('q1');
SELECT expect_msg('request without a reason', $$SELECT request_reschedule('   ')$$, 'Enter the reason');
SELECT expect_msg('request with a 501 character reason', $$SELECT request_reschedule(repeat('x', 501))$$, 'longer than 500');
SELECT act('q4'); SELECT expect_msg('request without a visit', $$SELECT request_reschedule('sick')$$, 'no booked visit');
SELECT act('q5'); SELECT expect_msg('request for an attended visit', $$SELECT request_reschedule('sick')$$, 'no booked visit');
SELECT act('ap'); SELECT expect_msg('a student with a request waiting asks again', $$SELECT request_reschedule('again')$$, 'already have a reschedule request');
SELECT act('q1');
SELECT request_reschedule('  family emergency  ');
SELECT expect_eq('request is pending, trimmed, and stamped with the asker',
  (SELECT status||'/'||reason||'/'||(requested_by = md5('q1')::uuid)::text||'/'||coalesce(decision_note, 'none') FROM reschedule_requests WHERE id = req_id('q1', 'pending')),
  'pending/family emergency/true/none');
SELECT expect_eq('a request does not move the visit', (SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Aq1')::uuid), md5('QF1')::uuid::text);
SELECT expect_msg('a second request while one is waiting', $$SELECT request_reschedule('again')$$, 'already have a reschedule request');
SELECT expect_eq('the request is audited with the asker',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'reschedule_requests' AND action = 'INSERT' AND actor_id = md5('q1')::uuid), '1');
SELECT act('q2'); SELECT request_reschedule('exam that day');
SELECT act('q3'); SELECT request_reschedule('sick');

-- who may answer: Registrar and Admin only
SELECT act('fn'); SELECT expect_msg('finance answers a request', $$SELECT decide_reschedule(req_id('q1','pending'), true, NULL, NULL)$$, 'Only the Registrar or Admin');
SELECT act('sc'); SELECT expect_msg('secretary answers a request', $$SELECT decide_reschedule(req_id('q1','pending'), true, NULL, NULL)$$, 'Only the Registrar or Admin');
SELECT act('q1'); SELECT expect_msg('the asker answers their own request', $$SELECT decide_reschedule(req_id('q1','pending'), true, NULL, NULL)$$, 'Only the Registrar or Admin');
SELECT expect_eq('refused answers changed nothing', (SELECT status FROM reschedule_requests WHERE id = req_id('q1','pending')), 'pending');

-- input refusals on q3's request leave it waiting
SELECT act('rg');
SELECT expect_msg('answer without a choice', $$SELECT decide_reschedule(req_id('q3','pending'), NULL, NULL, NULL)$$, 'Approve or decline');
SELECT expect_msg('answer a request that does not exist', $$SELECT decide_reschedule(md5('nobody')::uuid, true, NULL, NULL)$$, 'Request not found');
SELECT expect_msg('decline without a note', $$SELECT decide_reschedule(req_id('q3','pending'), false, NULL, NULL)$$, 'Enter the reason for declining');
SELECT expect_msg('decline with a blank note', $$SELECT decide_reschedule(req_id('q3','pending'), false, NULL, '   ')$$, 'Enter the reason for declining');
SELECT expect_msg('note of 501 characters', $$SELECT decide_reschedule(req_id('q3','pending'), false, NULL, repeat('x', 501))$$, 'longer than 500');
SELECT expect_fail('approve into a slot of another program', $$SELECT decide_reschedule(req_id('q3','pending'), true, md5('SR3')::uuid, NULL)$$);
SELECT expect_eq('input refusals left q3 waiting', (SELECT status FROM reschedule_requests WHERE id = req_id('q3','pending')), 'pending');

-- approve with no slot chosen: the next open slot on another date, and the note goes to the audit log
SELECT decide_reschedule(req_id('q1','pending'), true, NULL, 'ok to move');
SELECT expect_eq('approved: row, slot given, decider and note',
  (SELECT status||'/'||new_slot_id::text||'/'||(decided_by = md5('rg')::uuid)::text||'/'||(decided_at IS NOT NULL)::text||'/'||decision_note FROM reschedule_requests WHERE id = req_id('q1','approved')),
  'approved/'||md5('QF2')::uuid::text||'/true/true/ok to move');
SELECT expect_eq('approved: the visit moved to the next date, same booking row',
  (SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Aq1')::uuid)||'/'||(SELECT count(*)::text FROM visit_bookings WHERE applicant_id = md5('Aq1')::uuid),
  md5('QF2')::uuid::text||'/1');
SELECT expect_eq('approved: q1 was told once, with the visit moved notification',
  (SELECT count(*)::text||'/'||min(email_status) FROM notifications WHERE user_id = md5('q1')::uuid AND kind = 'visit_moved'), '1/pending');
SELECT expect_eq('approved: audit reason carries the note',
  (SELECT reason FROM audit_log WHERE table_name = 'visit_bookings' AND action = 'UPDATE'
     AND new_data->>'applicant_id' = md5('Aq1')::uuid::text AND new_data->>'slot_id' = md5('QF2')::uuid::text),
  'Reschedule request approved: ok to move');
SELECT expect_msg('answer the same request twice', $$SELECT decide_reschedule(req_id('q1','approved'), false, NULL, 'no')$$, 'already been decided');
SELECT expect_eq('the decision is audited with the registrar',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'reschedule_requests' AND action = 'UPDATE' AND actor_id = md5('rg')::uuid AND new_data->>'status' = 'approved'), '1');

-- approve into a chosen slot, by Admin, no note
SELECT act('ad');
SELECT decide_reschedule(req_id('q2','pending'), true, md5('QF3')::uuid, NULL);
SELECT expect_eq('chosen slot: q2 is in QF3, decided by admin',
  (SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Aq2')::uuid)||'/'||(SELECT (decided_by = md5('ad')::uuid)::text FROM reschedule_requests WHERE id = req_id('q2','approved')),
  md5('QF3')::uuid::text||'/true');
SELECT expect_eq('chosen slot without a note: audit reason has no colon',
  (SELECT reason FROM audit_log WHERE table_name = 'visit_bookings' AND action = 'UPDATE'
     AND new_data->>'applicant_id' = md5('Aq2')::uuid::text AND new_data->>'slot_id' = md5('QF3')::uuid::text),
  'Reschedule request approved');

-- a refused move rolls everything back: q3 into the full QF3
SELECT act('rg');
SELECT expect_fail('approve into a full slot', $$SELECT decide_reschedule(req_id('q3','pending'), true, md5('QF3')::uuid, NULL)$$);
SELECT expect_eq('refused move: request waiting, visit unchanged, nobody told',
  (SELECT count(*)::text FROM reschedule_requests WHERE booking_id = (SELECT id FROM visit_bookings WHERE applicant_id = md5('Aq3')::uuid) AND status = 'pending')||'/'||
  (SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Aq3')::uuid)||'/'||
  (SELECT count(*)::text FROM notifications WHERE user_id = md5('q3')::uuid), '1/'||md5('QF1')::uuid::text||'/0');

-- decline: note required, the visit stays, the person is told
SELECT decide_reschedule(req_id('q3','pending'), false, NULL, 'No seats left that week');
SELECT expect_eq('declined: row, decider and note, no new slot',
  (SELECT status||'/'||(decided_by = md5('rg')::uuid)::text||'/'||(decided_at IS NOT NULL)::text||'/'||decision_note||'/'||(new_slot_id IS NULL)::text FROM reschedule_requests WHERE id = req_id('q3','declined')),
  'declined/true/true/No seats left that week/true');
SELECT expect_eq('declined: the visit did not move and no visit moved notification was written',
  (SELECT slot_id::text FROM visit_bookings WHERE applicant_id = md5('Aq3')::uuid)||'/'||
  (SELECT count(*)::text FROM notifications WHERE user_id = md5('q3')::uuid AND kind = 'visit_moved'), md5('QF1')::uuid::text||'/0');
SELECT expect_eq('declined: q3 was told once, with the note',
  (SELECT count(*)::text||'/'||(min(message) LIKE '%No seats left that week%')::text||'/'||min(email_status) FROM notifications WHERE user_id = md5('q3')::uuid AND kind = 'reschedule_declined'), '1/true/pending');
SELECT expect_eq('declined: audited as a decline by the registrar',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'reschedule_requests' AND action = 'UPDATE' AND actor_id = md5('rg')::uuid AND new_data->>'status' = 'declined'), '1');

-- after a decline the person may ask again
SELECT act('q3'); SELECT request_reschedule('second try');
SELECT expect_eq('q3 has two requests, one waiting', (SELECT count(*)::text||'/'||count(*) FILTER (WHERE rr.status = 'pending')::text FROM reschedule_requests rr JOIN visit_bookings b ON b.id = rr.booking_id WHERE b.applicant_id = md5('Aq3')::uuid), '2/1');

-- approve with nothing open on another date: refused with a clear message, still waiting
SELECT act('rg');
SELECT expect_msg('approve with no open slot on another date', $$SELECT decide_reschedule(req_id('q3','pending'), true, NULL, NULL)$$, 'No open slot');
SELECT expect_eq('no slot: request still waiting', (SELECT count(*)::text FROM reschedule_requests WHERE id = req_id('q3','pending') AND status = 'pending'), '1');

-- approve after the visit was marked attended: refused
UPDATE visit_bookings SET status = 'attended' WHERE applicant_id = md5('Aq3')::uuid;
SELECT expect_msg('approve a visit already marked attended', $$SELECT decide_reschedule(req_id('q3','pending'), true, md5('QF2')::uuid, NULL)$$, 'already marked attended');

-- a reschedule moved visits only
SELECT expect_eq('student count unchanged by every reschedule', (SELECT count(*)::text FROM students), (SELECT students FROM snap12));

-- row level security as the signed-in roles
SELECT id AS q1_booking FROM visit_bookings WHERE applicant_id = md5('Aq1')::uuid \gset
\if :has_auth
SET ROLE authenticated;
SELECT act('q3'); SELECT expect_eq('an applicant reads only their own requests', (SELECT count(*)::text FROM reschedule_requests), '2');
SELECT act('q1'); SELECT expect_eq('another applicant reads only theirs', (SELECT count(*)::text FROM reschedule_requests), '1');
SELECT act('q4'); SELECT expect_eq('an applicant with no request reads none', (SELECT count(*)::text FROM reschedule_requests), '0');
SELECT act('fn'); SELECT expect_eq('finance reads no request', (SELECT count(*)::text FROM reschedule_requests), '0');
SELECT act('sc'); SELECT expect_eq('secretary reads no request', (SELECT count(*)::text FROM reschedule_requests), '0');
SELECT act('rg'); SELECT expect_eq('registrar reads requests', ((SELECT count(*) FROM reschedule_requests) > 0)::text, 'true');
SELECT act('ad'); SELECT expect_eq('admin reads requests', ((SELECT count(*) FROM reschedule_requests) > 0)::text, 'true');
SELECT act('rg'); SELECT expect_eq('registrar reads the mass reschedule record', ((SELECT count(*) FROM mass_reschedules) > 0)::text, 'true');
SELECT act('q1'); SELECT expect_eq('an applicant reads no mass reschedule record', (SELECT count(*)::text FROM mass_reschedules), '0');
SELECT act('q4');
SELECT expect_fail('an applicant files a request for another applicant visit',
  format('INSERT INTO reschedule_requests (booking_id, requested_by, reason) VALUES (%L, %L, %L)', :'q1_booking', md5('q4')::uuid, 'x'));
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 12 row level security checks not run';
\endif

-- ============================================================
-- schedule changes after the slip (step 16), 20261025180000_schedule_changes.sql.
-- Own program BSQ (college 1) with one section, two students with a slip, and a
-- Dean of college 2 for the "another college" refusal. The term is set by now.
-- ============================================================
SELECT act('ad');
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000f1','BSS16','Test Program S16','00000000-0000-0000-0000-0000000000c1');
INSERT INTO subjects (id,program_id,code,title,units,year_level) VALUES (md5('Q1')::uuid,'00000000-0000-0000-0000-0000000000f1','Q101','Q one',3,1);
INSERT INTO rooms (id,name,college_id) VALUES (md5('RMQ1')::uuid,'Room Q1',NULL),(md5('RMQ2')::uuid,'Room Q2',NULL);
INSERT INTO auth.users (id,email) VALUES (md5('pf3')::uuid,'pf3@x.ph'),(md5('pf4')::uuid,'pf4@x.ph'),(md5('dn2')::uuid,'dn2@x.ph');
INSERT INTO users (id,auth_id,full_name,email,role,college_id) VALUES
  (md5('pf3')::uuid, md5('pf3')::uuid,'pf3','pf3@x.ph','professor',NULL),
  (md5('pf4')::uuid, md5('pf4')::uuid,'pf4','pf4@x.ph','professor',NULL),
  (md5('dn2')::uuid, md5('dn2')::uuid,'dn2','dn2@x.ph','dean','00000000-0000-0000-0000-0000000000c2');
SELECT mk_applicant('k1','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT mk_applicant('k2','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES
  (md5('SQA')::uuid,'00000000-0000-0000-0000-0000000000f1','A',1,10),
  (md5('SQD')::uuid,'00000000-0000-0000-0000-0000000000f1','D',1,10);
UPDATE section_subjects SET professor_id=md5('pf4')::uuid, room_id=md5('RMQ1')::uuid, day_of_week=1, start_time='08:00', end_time='09:00' WHERE section_id=md5('SQA')::uuid;
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('SQA')::uuid;
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('SQA')::uuid;
SELECT act('rg'); UPDATE sections SET schedule_status = 'approved' WHERE id = md5('SQA')::uuid;
INSERT INTO students (applicant_id,student_number,documents_received_by) SELECT md5('Ak'||n)::uuid,'x',md5('rg')::uuid FROM generate_series(1,2) n;
SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid));
SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ak2')::uuid));
SELECT expect_eq('both students are in the approved section',
  (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SQA')::uuid), '2');
SELECT expect_eq('slip stored its schedule', (SELECT jsonb_array_length(schedule)::text||'/'||(schedule->0->>'day') FROM assessment_slips WHERE student_id = (SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid)), '1/1');
SELECT expect_eq('nothing changed yet', (SELECT my_schedule_changed()::text), 'false');
SELECT act('k1'); SELECT expect_eq('student: no change flagged yet', (SELECT my_schedule_changed()::text), 'false');

-- who may change an approved schedule, and what is refused
SELECT act('sc');
SELECT ss.id AS q_row FROM section_subjects ss WHERE ss.section_id = md5('SQA')::uuid \gset
SELECT ss.id AS q_draft_row FROM section_subjects ss WHERE ss.section_id = md5('SQD')::uuid \gset
SELECT expect_msg('direct edit of an approved section is still locked',
  format($$UPDATE section_subjects SET day_of_week = 2 WHERE id = %L$$, :'q_row'), 'locked');
SELECT expect_msg('no reason', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', '  ')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'reason is required');
SELECT expect_msg('draft section', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', 'x')$$, :'q_draft_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'Only an approved schedule');
SELECT expect_msg('unknown subject row', $$SELECT amend_schedule(md5('nope')::uuid, NULL, NULL, NULL, NULL, NULL, 'x')$$, 'Subject not found');
SELECT act('dn2'); SELECT expect_msg('dean of another college', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', 'x')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'another college');
SELECT act('pf3'); SELECT expect_msg('professor', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', 'x')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'Only the College Secretary');
SELECT act('rg'); SELECT expect_msg('registrar', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', 'x')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'Only the College Secretary');
SELECT act('k1'); SELECT expect_msg('student', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', 'x')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'Only the College Secretary');
SELECT act('sc');
SELECT expect_msg('not a professor', format($$SELECT amend_schedule(%L, %L, %L, 2::smallint, '09:00', '10:00', 'x')$$, :'q_row', md5('rg')::uuid, md5('RMQ2')::uuid), 'not an active Professor');
SELECT expect_eq('refusals changed nothing',
  (SELECT day_of_week::text||'/'||(professor_id = md5('pf4')::uuid)::text FROM section_subjects WHERE id = :'q_row'), '1/true');
SELECT expect_eq('refusals told nobody', (SELECT count(*)::text FROM notifications WHERE kind = 'schedule_changed'), '0');

-- a clash is still refused: pf3 teaches the draft section on Wednesday 10:00 to 11:00
UPDATE section_subjects SET professor_id=md5('pf3')::uuid, room_id=md5('RMQ2')::uuid, day_of_week=3, start_time='10:00', end_time='11:00' WHERE id = :'q_draft_row';
SELECT expect_fail('professor clash on a change', format($$SELECT amend_schedule(%L, %L, %L, 3::smallint, '10:30', '11:30', 'x')$$, :'q_row', md5('pf3')::uuid, md5('RMQ1')::uuid));
SELECT expect_fail('room clash on a change', format($$SELECT amend_schedule(%L, %L, %L, 3::smallint, '10:30', '11:30', 'x')$$, :'q_row', md5('pf2')::uuid, md5('RMQ2')::uuid));

-- the Secretary changes it: Tuesday 09:00 to 10:00, another professor and room
SELECT amend_schedule(:'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid, 2::smallint, '09:00', '10:00', 'Professor on leave');
SELECT expect_eq('the section row has the new loading',
  (SELECT day_of_week::text||'/'||to_char(start_time,'HH24:MI')||'/'||(professor_id = md5('pf3')::uuid)::text||'/'||(room_id = md5('RMQ2')::uuid)::text FROM section_subjects WHERE id = :'q_row'),
  '2/09:00/true/true');
SELECT expect_eq('the section stays approved', (SELECT schedule_status FROM sections WHERE id = md5('SQA')::uuid), 'approved');
SELECT act('rg');
SELECT expect_eq('the slip still shows the first schedule',
  (SELECT (assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid))->'subjects'->0->>'day')||'/'||(assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid))->'subjects'->0->>'start')||'/'||(assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid))->'subjects'->0->>'professor')), '1/08:00/pf4');
SELECT expect_eq('each placed student was told once',
  (SELECT count(*)::text||'/'||count(DISTINCT user_id)::text||'/'||min(email_status) FROM notifications WHERE kind = 'schedule_changed'), '2/2/pending');
SELECT expect_eq('the audit log has who and why',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'section_subjects' AND action = 'UPDATE' AND record_id = :'q_row'
     AND actor_id = md5('sc')::uuid AND reason = 'Professor on leave'), '1');
SELECT act('k1'); SELECT expect_eq('student: change flagged', (SELECT my_schedule_changed()::text), 'true');
SELECT act('rg'); SELECT expect_eq('registrar is not a student: no flag', (SELECT my_schedule_changed()::text), 'false');

-- the COR shows the final schedule and keeps it
SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid));
SELECT expect_eq('COR shows the final schedule',
  (SELECT (certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid))->'subjects'->0->>'day')||'/'||(certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid))->'subjects'->0->>'professor')), '2/pf3');
SELECT expect_eq('the slip of the same student is still the first schedule',
  (SELECT assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Ak1')::uuid))->'subjects'->0->>'day'), '1');
SELECT act('k1'); SELECT expect_eq('student with a COR: no flag', (SELECT my_schedule_changed()::text), 'false');
SELECT act('k2'); SELECT expect_eq('section-mate without a COR: still flagged', (SELECT my_schedule_changed()::text), 'true');

-- once any student of the section has a COR, the section is locked
SELECT act('sc');
SELECT expect_msg('change after a COR in the section', format($$SELECT amend_schedule(%L, %L, %L, 4::smallint, '09:00', '10:00', 'late change')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'COR was already issued');
SELECT expect_eq('the refusal left the loading alone', (SELECT day_of_week::text FROM section_subjects WHERE id = :'q_row'), '2');

-- the whole path still works for the other student's COR, and the old COR is untouched
SELECT act('rg');
SELECT issue_cor((SELECT id FROM students WHERE applicant_id = md5('Ak2')::uuid));
SELECT expect_eq('second COR shows the same final schedule',
  (SELECT certificate_of_registration((SELECT id FROM students WHERE applicant_id = md5('Ak2')::uuid))->'subjects'->0->>'day'), '2');

-- row level security: the new functions answer for the signed-in student only, and the builder is internal
\if :has_auth
SET ROLE authenticated;
SELECT act('k2'); SELECT expect_eq('authenticated student calls my_schedule_changed', (SELECT my_schedule_changed()::text), 'false');
SELECT expect_fail('authenticated calls the schedule builder', format($$SELECT student_schedule_json(%L)$$, md5('nobody')::uuid));
SELECT act('sc');
SELECT expect_msg('authenticated secretary reaches amend_schedule (refused by the COR rule, not by a missing grant)',
  format($$SELECT amend_schedule(%L, %L, %L, 4::smallint, '09:00', '10:00', 'x')$$, :'q_row', md5('pf3')::uuid, md5('RMQ2')::uuid), 'COR was already issued');
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 16 grant checks not run';
\endif

-- ============================================================
-- withdrawals (step 17), 20261025190000_withdrawals.sql.
-- Visit slots and seats are released, a withdrawn person is left alone by every
-- function that hands out a slot, a seat or a COR, and the columns cannot be
-- written any other way.
-- ============================================================
SELECT act('ad');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring)
  VALUES (md5('WS1')::uuid,'00000000-0000-0000-0000-0000000000f1',mnl_today()+9,'09:00','10:00',1,'Registrar Office W','x');
SELECT mk_applicant('wd1','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT mk_applicant('wd2','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT mk_applicant('wd3','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT mk_applicant('wd4','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT act('rg');
SELECT assign_visit_slot(md5('Awd1')::uuid, md5('WS1')::uuid);
SELECT expect_fail('the one-seat slot is full for w2', format($$SELECT assign_visit_slot(%L, %L)$$, md5('Awd2')::uuid, md5('WS1')::uuid));

-- an applicant withdraws: the visit slot opens
SELECT act('wd1');
SELECT expect_msg('empty reason', $$SELECT withdraw_my_enrollment('   ')$$, 'Enter the reason');
SELECT expect_msg('reason over 500 characters', format($$SELECT withdraw_my_enrollment(%L)$$, repeat('x', 501)), 'longer than 500');
SELECT withdraw_my_enrollment('Enrolling somewhere else');
SELECT expect_eq('w1 is marked withdrawn', (SELECT (withdrawn_at IS NOT NULL AND withdrawn_by = md5('wd1')::uuid)::text FROM applicants WHERE id = md5('Awd1')::uuid), 'true');
SELECT expect_eq('w1 reason stored', (SELECT withdrawn_reason FROM applicants WHERE id = md5('Awd1')::uuid), 'Enrolling somewhere else');
SELECT expect_eq('w1 booking is gone', (SELECT count(*)::text FROM visit_bookings WHERE applicant_id = md5('Awd1')::uuid), '0');
SELECT expect_eq('slot has no bookings left', (SELECT count(*)::text FROM visit_bookings WHERE slot_id = md5('WS1')::uuid), '0');
SELECT expect_eq('w1 was told', (SELECT count(*)::text FROM notifications WHERE user_id = md5('wd1')::uuid AND kind = 'withdrawn' AND message LIKE 'You withdrew%'), '1');
SELECT expect_eq('the withdrawal is audited with the reason', (SELECT count(*)::text FROM audit_log WHERE table_name = 'applicants' AND action = 'UPDATE' AND record_id = md5('Awd1')::uuid::text AND reason = 'Enrolling somewhere else' AND actor_id = md5('wd1')::uuid), '1');
SELECT expect_eq('the booking delete is audited with the reason', (SELECT count(*)::text FROM audit_log WHERE table_name = 'visit_bookings' AND action = 'DELETE' AND reason = 'Enrolling somewhere else'), '1');
SELECT expect_msg('already withdrawn', $$SELECT withdraw_my_enrollment('again')$$, 'already withdrawn');

-- the freed slot can be used, and the withdrawn applicant is skipped everywhere
SELECT act('rg');
SELECT assign_visit_slot(md5('Awd2')::uuid, md5('WS1')::uuid);
SELECT expect_eq('w2 took the freed slot', (SELECT count(*)::text FROM visit_bookings WHERE slot_id = md5('WS1')::uuid AND applicant_id = md5('Awd2')::uuid), '1');
SELECT expect_msg('assign a slot to a withdrawn applicant', format($$SELECT assign_visit_slot(%L, %L)$$, md5('Awd1')::uuid, md5('WS1')::uuid), 'has withdrawn');
SELECT expect_eq('automatic assignment skips a withdrawn applicant', (SELECT (auto_assign_visit(md5('Awd1')::uuid) IS NULL)::text), 'true');
SELECT act('ad');
INSERT INTO visit_slots (id,program_id,slot_date,start_time,end_time,capacity,office_name,what_to_bring)
  VALUES (md5('WS2')::uuid,'00000000-0000-0000-0000-0000000000f1',mnl_today()+9,'10:00','11:00',5,'Registrar Office W2','x');
SELECT act('rg');
SELECT expect_eq('bulk assignment books w3 and w4, not w1', (SELECT assigned::text FROM assign_unassigned_visits('00000000-0000-0000-0000-0000000000f1')), '2');
SELECT expect_eq('w1 still has no booking', (SELECT count(*)::text FROM visit_bookings WHERE applicant_id = md5('Awd1')::uuid), '0');
SELECT expect_eq('nobody is left over', (SELECT left_over::text FROM assign_unassigned_visits('00000000-0000-0000-0000-0000000000f1')), '0');
SELECT expect_msg('promote a withdrawn applicant', format($$SELECT mark_documents_received(%L)$$, md5('Awd1')::uuid), 'has withdrawn');

-- the columns cannot be written any other way (Admin and superuser included)
SELECT expect_msg('set withdrawn directly', format($$UPDATE applicants SET withdrawn_at = now(), withdrawn_by = %L, withdrawn_reason = 'x' WHERE id = %L$$, md5('rg')::uuid, md5('Awd3')::uuid), 'Use the withdraw action');
SELECT expect_msg('undo a withdrawal directly', format($$UPDATE applicants SET withdrawn_at = NULL, withdrawn_by = NULL, withdrawn_reason = NULL WHERE id = %L$$, md5('Awd1')::uuid), 'Use the withdraw action');
SELECT expect_fail('half a withdrawal', format($$SELECT set_config('app.withdrawing','on',false); UPDATE applicants SET withdrawn_at = now() WHERE id = %L$$, md5('Awd3')::uuid));
SELECT set_config('app.withdrawing', '', false);

-- who may withdraw whom
SELECT act('pf3'); SELECT expect_msg('professor withdraws herself', $$SELECT withdraw_my_enrollment('x')$$, 'Only an applicant or student');
SELECT act('wd3'); SELECT expect_msg('applicant withdraws someone else', format($$SELECT withdraw_applicant(%L, 'x')$$, md5('Awd4')::uuid), 'Only the Registrar or Admin');
SELECT act('fn'); SELECT expect_msg('finance withdraws', format($$SELECT withdraw_applicant(%L, 'x')$$, md5('Awd4')::uuid), 'Only the Registrar or Admin');
SELECT act('rg'); SELECT expect_msg('unknown applicant', format($$SELECT withdraw_applicant(%L, 'x')$$, md5('nobody')::uuid), 'Applicant not found');
SELECT expect_msg('staff needs a reason too', format($$SELECT withdraw_applicant(%L, '')$$, md5('Awd4')::uuid), 'Enter the reason');

-- a pending reschedule request goes with the booking
SELECT act('wd4'); SELECT request_reschedule('Cannot make it that day');
SELECT expect_eq('w4 has a pending request', (SELECT count(*)::text FROM reschedule_requests rr JOIN visit_bookings b ON b.id = rr.booking_id WHERE b.applicant_id = md5('Awd4')::uuid AND rr.status = 'pending'), '1');
SELECT act('rg'); SELECT withdraw_applicant(md5('Awd4')::uuid, 'No answer after three calls');
SELECT expect_eq('w4 booking and request are gone', (SELECT (SELECT count(*) FROM visit_bookings WHERE applicant_id = md5('Awd4')::uuid)::text || '/' || (SELECT count(*) FROM reschedule_requests WHERE reason = 'Cannot make it that day')::text), '0/0');
SELECT expect_eq('w4 is told it was the Registrar', (SELECT count(*)::text FROM notifications WHERE user_id = md5('wd4')::uuid AND kind = 'withdrawn' AND message LIKE 'The Registrar withdrew%No answer%'), '1');
SELECT expect_eq('w4 was withdrawn by the registrar', (SELECT (withdrawn_by = md5('rg')::uuid)::text FROM applicants WHERE id = md5('Awd4')::uuid), 'true');

-- seats: a one-seat section, one student in it, two waiting
SELECT act('ad');
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000f7','BSW17','Test Program W17','00000000-0000-0000-0000-0000000000c1');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SWX')::uuid,'00000000-0000-0000-0000-0000000000f7','A',1,1);
SELECT mk_applicant('wx1','00000000-0000-0000-0000-0000000000f7', mnl_today());
SELECT mk_applicant('wx2','00000000-0000-0000-0000-0000000000f7', mnl_today());
SELECT mk_applicant('wx3','00000000-0000-0000-0000-0000000000f7', mnl_today());
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Awx1')::uuid,'x',md5('rg')::uuid);
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Awx2')::uuid,'x',md5('rg')::uuid);
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Awx3')::uuid,'x',md5('rg')::uuid);
SELECT expect_eq('x1 holds the only seat', (SELECT st.applicant_id::text FROM student_sections ss JOIN students st ON st.id = ss.student_id WHERE ss.section_id = md5('SWX')::uuid), md5('Awx1')::uuid::text);
-- x1 has a pending payment, x3 has a cleared one
INSERT INTO payments (student_id) SELECT id FROM students WHERE applicant_id = md5('Awx1')::uuid;
INSERT INTO payments (student_id, amount_due, amount_paid, receipt_no, status, recorded_by, cleared_at)
  SELECT id, 100, 100, 'R-W17', 'cleared', md5('fn')::uuid, now() FROM students WHERE applicant_id = md5('Awx3')::uuid;

-- a waiting student withdraws: no seat to release, nobody else moves
SELECT withdraw_applicant(md5('Awx3')::uuid, 'Moved abroad');
SELECT expect_eq('x3 (waiting) withdrawn, x1 keeps the seat', (SELECT st.applicant_id::text FROM student_sections ss JOIN students st ON st.id = ss.student_id WHERE ss.section_id = md5('SWX')::uuid), md5('Awx1')::uuid::text);
SELECT expect_eq('x3 cleared payment stays', (SELECT count(*)::text FROM payments p JOIN students st ON st.id = p.student_id WHERE st.applicant_id = md5('Awx3')::uuid AND p.status = 'cleared'), '1');
SELECT expect_eq('x3 student number is kept', (SELECT count(*)::text FROM students WHERE applicant_id = md5('Awx3')::uuid AND student_number IS NOT NULL AND student_number <> 'x'), '1');

-- the seated student withdraws: seat released, the next waiting student (x2, not x3) takes it
SELECT act('wx1');
SELECT withdraw_my_enrollment('Changed my mind');
SELECT expect_eq('x1 no longer has a seat', (SELECT count(*)::text FROM student_sections ss JOIN students st ON st.id = ss.student_id WHERE st.applicant_id = md5('Awx1')::uuid), '0');
SELECT expect_eq('x2 was seated on the freed seat', (SELECT st.applicant_id::text FROM student_sections ss JOIN students st ON st.id = ss.student_id WHERE ss.section_id = md5('SWX')::uuid), md5('Awx2')::uuid::text);
SELECT expect_eq('x2 was told about the section', (SELECT count(*)::text FROM notifications WHERE user_id = md5('wx2')::uuid AND kind = 'section_placed'), '1');
SELECT expect_eq('x1 pending payment is gone', (SELECT count(*)::text FROM payments p JOIN students st ON st.id = p.student_id WHERE st.applicant_id = md5('Awx1')::uuid), '0');
SELECT expect_eq('x1 student row stays', (SELECT count(*)::text FROM students WHERE applicant_id = md5('Awx1')::uuid), '1');

-- more seats open: the withdrawn x3 and x1 are still not seated
SELECT act('sc');
UPDATE sections SET capacity = 5 WHERE id = md5('SWX')::uuid;
SELECT expect_eq('withdrawn students are not seated when capacity grows', (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SWX')::uuid), '1');
SELECT expect_msg('move a withdrawn student into a section', format($$SELECT move_student_section((SELECT id FROM students WHERE applicant_id = md5('Awx3')::uuid), %L)$$, md5('SWX')::uuid), 'has withdrawn');

-- a COR holder: the student cannot withdraw alone, the Registrar can
SELECT act('k1');
SELECT expect_msg('student with a COR withdraws herself', $$SELECT withdraw_my_enrollment('x')$$, 'already enrolled');
SELECT act('rg');
SELECT expect_eq('Ak2 has a COR and a seat before', (SELECT (SELECT count(*) FROM cors c JOIN students st ON st.id = c.student_id WHERE st.applicant_id = md5('Ak2')::uuid)::text || '/' || (SELECT count(*) FROM student_sections ss JOIN students st ON st.id = ss.student_id WHERE st.applicant_id = md5('Ak2')::uuid)::text), '1/1');
SELECT withdraw_applicant(md5('Ak2')::uuid, 'Transferred to another school');
SELECT expect_eq('Ak2 COR stays as history, the seat is gone', (SELECT (SELECT count(*) FROM cors c JOIN students st ON st.id = c.student_id WHERE st.applicant_id = md5('Ak2')::uuid)::text || '/' || (SELECT count(*) FROM student_sections ss JOIN students st ON st.id = ss.student_id WHERE st.applicant_id = md5('Ak2')::uuid)::text), '1/0');

-- the bulk COR issue skips a withdrawn student with a slip instead of stopping
SELECT act('ad');
SELECT mk_applicant('wk3','00000000-0000-0000-0000-0000000000f1', mnl_today());
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Awk3')::uuid,'x',md5('rg')::uuid);
SELECT issue_assessment_slip((SELECT id FROM students WHERE applicant_id = md5('Awk3')::uuid));
SELECT withdraw_applicant(md5('Awk3')::uuid, 'Did not pay');
SELECT expect_msg('COR for a withdrawn student', format($$SELECT issue_cor(%L)$$, (SELECT id FROM students WHERE applicant_id = md5('Awk3')::uuid)), 'has withdrawn');
SELECT expect_eq('issue_all_ready_cors does not stop on a withdrawn student', (SELECT (issued >= 0)::text FROM issue_all_ready_cors()), 'true');
SELECT expect_eq('Ak3 still has no COR', (SELECT count(*)::text FROM cors c JOIN students st ON st.id = c.student_id WHERE st.applicant_id = md5('Awk3')::uuid), '0');

-- row level security: the signed-in role can call the two entry points but not the core
\if :has_auth
SET ROLE authenticated;
SELECT act('wd3');
SELECT withdraw_my_enrollment('Authenticated call works');
SELECT expect_eq('authenticated applicant withdrew', (SELECT (withdrawn_at IS NOT NULL)::text FROM applicants WHERE id = md5('Awd3')::uuid), 'true');
SELECT expect_fail('authenticated calls the core', format($$SELECT withdraw_enrollment_core(%L, 'x')$$, md5('Ak1')::uuid));
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 17 grant checks not run';
\endif

-- ============================================================
-- terms foundation (step 18), 20261026010000_terms_foundation.sql.
-- Own program BST18. One student gets a slip, a payment and a COR in the 1st
-- semester, then the same three in the 2nd semester, in a section that has the same
-- name as the first one. The current term is the 2nd semester again at the end.
-- ============================================================
SELECT act('ad');
UPDATE enrollment_term SET school_year = '2026-2027', semester = '1st';
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000f8','BST18','Test Program T18','00000000-0000-0000-0000-0000000000c1');
UPDATE program_payment_settings SET payment_required = true WHERE program_id = '00000000-0000-0000-0000-0000000000f8';
INSERT INTO auth.users (id,email) VALUES (md5('pf18')::uuid,'pf18@x.ph');
INSERT INTO users (id,auth_id,full_name,email,role,college_id)
  VALUES (md5('pf18')::uuid, md5('pf18')::uuid,'pf18','pf18@x.ph','professor',NULL);
INSERT INTO rooms (id,name,college_id) VALUES (md5('RM18')::uuid,'Room 18',NULL);
INSERT INTO subjects (id,program_id,code,title,units,year_level,semester) VALUES
  (md5('T181')::uuid,'00000000-0000-0000-0000-0000000000f8','T181','T one',3,1,'1st'),
  (md5('T182')::uuid,'00000000-0000-0000-0000-0000000000f8','T182','T two',3,1,'2nd');
INSERT INTO subjects (id,program_id,code,title,units,year_level) VALUES
  (md5('T183')::uuid,'00000000-0000-0000-0000-0000000000f8','T183','T three',3,1);
SELECT expect_eq('a subject added without a semester takes the semester of the term', (SELECT semester FROM subjects WHERE id = md5('T183')::uuid), '1st');
SELECT expect_fail('a summer-only subject cannot also be flagged for summer', $$INSERT INTO subjects (program_id,code,title,units,year_level,semester,offered_in_summer) VALUES ('00000000-0000-0000-0000-0000000000f8','T184','T four',3,1,'summer',true)$$);
SELECT mk_applicant('t1','00000000-0000-0000-0000-0000000000f8', mnl_today());

-- the 1st semester section
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('ST18A')::uuid,'00000000-0000-0000-0000-0000000000f8','A',1,10);
SELECT expect_eq('a new section takes the current term', (SELECT school_year||'/'||semester FROM sections WHERE id = md5('ST18A')::uuid), '2026-2027/1st');
SELECT expect_eq('the section holds only the subjects of its semester',
  (SELECT string_agg(sub.code, ',' ORDER BY sub.code) FROM section_subjects ss JOIN subjects sub ON sub.id = ss.subject_id WHERE ss.section_id = md5('ST18A')::uuid), 'T181,T183');
UPDATE section_subjects SET professor_id=md5('pf18')::uuid, room_id=md5('RM18')::uuid, day_of_week=1, start_time='08:00', end_time='09:00' WHERE section_id=md5('ST18A')::uuid AND subject_id=md5('T181')::uuid;
UPDATE section_subjects SET professor_id=md5('pf18')::uuid, room_id=md5('RM18')::uuid, day_of_week=1, start_time='09:00', end_time='10:00' WHERE section_id=md5('ST18A')::uuid AND subject_id=md5('T183')::uuid;
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('ST18A')::uuid;
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('ST18A')::uuid;
SELECT act('rg'); UPDATE sections SET schedule_status = 'approved' WHERE id = md5('ST18A')::uuid;
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('At1')::uuid,'x',md5('rg')::uuid);
SELECT id AS t18_student FROM students WHERE applicant_id = md5('At1')::uuid \gset
SELECT expect_eq('the new student is enrolled in the 1st semester section',
  (SELECT section_id::text||'/'||school_year||'/'||semester FROM student_sections WHERE student_id = :'t18_student'),
  md5('ST18A')::uuid::text||'/2026-2027/1st');
SELECT issue_assessment_slip(:'t18_student');
SELECT act('fn'); SELECT record_payment(:'t18_student', 1000, 1000, 'T18-1');
SELECT act('rg'); SELECT issue_cor(:'t18_student');
SELECT expect_eq('1st semester: one slip, one payment, one COR, each stamped with the term',
  (SELECT (SELECT count(*) FROM assessment_slips WHERE student_id = :'t18_student' AND school_year = '2026-2027' AND semester = '1st')::text||'/'||
          (SELECT count(*) FROM payments WHERE student_id = :'t18_student' AND school_year = '2026-2027' AND semester = '1st')::text||'/'||
          (SELECT count(*) FROM cors WHERE student_id = :'t18_student' AND school_year = '2026-2027' AND semester = '1st')::text), '1/1/1');

-- the 2nd semester: the same section name is allowed, and a student already enrolled is not placed again
SELECT act('ad'); UPDATE enrollment_term SET semester = '2nd';
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('ST18B')::uuid,'00000000-0000-0000-0000-0000000000f8','A',1,10);
SELECT expect_eq('the same section name exists in two terms',
  (SELECT count(*)::text FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000f8' AND year_level = 1 AND name = 'A'), '2');
SELECT expect_eq('the 2nd semester section holds only 2nd semester subjects',
  (SELECT string_agg(sub.code, ',' ORDER BY sub.code) FROM section_subjects ss JOIN subjects sub ON sub.id = ss.subject_id WHERE ss.section_id = md5('ST18B')::uuid), 'T182');
SELECT expect_eq('a student who is enrolled is not placed again by a new section',
  (SELECT count(*)::text FROM student_sections WHERE student_id = :'t18_student'), '1');
UPDATE section_subjects SET professor_id=md5('pf18')::uuid, room_id=md5('RM18')::uuid, day_of_week=2, start_time='08:00', end_time='09:00' WHERE section_id=md5('ST18B')::uuid;
UPDATE sections SET schedule_status = 'pending_dean' WHERE id = md5('ST18B')::uuid;
SELECT act('dn'); UPDATE sections SET schedule_status = 'dean_signed' WHERE id = md5('ST18B')::uuid;
SELECT act('rg'); UPDATE sections SET schedule_status = 'approved' WHERE id = md5('ST18B')::uuid;

-- a second enrollment for the same student (promotion is step 21, so it is inserted directly)
INSERT INTO student_sections (student_id, section_id) VALUES (:'t18_student', md5('ST18B')::uuid);
SELECT expect_eq('the second enrollment takes the term of its section',
  (SELECT school_year||'/'||semester FROM student_sections WHERE student_id = :'t18_student' AND section_id = md5('ST18B')::uuid), '2026-2027/2nd');
SELECT expect_eq('the student holds two enrollments', (SELECT count(*)::text FROM student_sections WHERE student_id = :'t18_student'), '2');
SELECT act('sc');
SELECT expect_msg('move into a section of an earlier term',
  format($$SELECT move_student_section(%L, %L)$$, :'t18_student', md5('ST18A')::uuid), 'current term');
SELECT act('rg');
SELECT expect_eq('the student is ready for a slip in the new term', (SELECT count(*)::text FROM slip_ready_students() WHERE student_id = :'t18_student'), '1');
SELECT issue_assessment_slip(:'t18_student');
SELECT expect_msg('slip issued twice in one term', format($$SELECT issue_assessment_slip(%L)$$, :'t18_student'), 'already issued');
SELECT act('fn'); SELECT record_payment(:'t18_student', 2000, 2000, 'T18-2');
SELECT act('rg');
SELECT expect_eq('the student is ready for a COR in the new term', (SELECT count(*)::text FROM cor_ready_students() WHERE student_id = :'t18_student'), '1');
SELECT issue_cor(:'t18_student');
SELECT expect_msg('COR issued twice in one term', format($$SELECT issue_cor(%L)$$, :'t18_student'), 'already issued');
SELECT expect_eq('one student, two terms: two slips, two payments, two CORs',
  (SELECT (SELECT count(*) FROM assessment_slips WHERE student_id = :'t18_student')::text||'/'||
          (SELECT count(*) FROM payments WHERE student_id = :'t18_student')::text||'/'||
          (SELECT count(*) FROM cors WHERE student_id = :'t18_student')::text), '2/2/2');
SELECT expect_eq('the payment of each term kept its own amounts',
  (SELECT string_agg(semester||':'||amount_paid::text, ',' ORDER BY semester) FROM payments WHERE student_id = :'t18_student'), '1st:1000.00,2nd:2000.00');
SELECT expect_eq('the 1st semester slip kept its own schedule',
  (SELECT schedule->0->>'code' FROM assessment_slips WHERE student_id = :'t18_student' AND semester = '1st'), 'T181');
SELECT expect_eq('the slip read for the student is the 2nd semester one', (SELECT assessment_slip(:'t18_student')->'subjects'->0->>'code'), 'T182');
SELECT expect_eq('the COR read for the student is the 2nd semester one',
  (SELECT (certificate_of_registration(:'t18_student')->>'semester')||'/'||(certificate_of_registration(:'t18_student')->>'amountPaid')), '2nd/2000.00');
SELECT expect_eq('nobody is left ready after both CORs', (SELECT count(*)::text FROM cor_ready_students() WHERE student_id = :'t18_student'), '0');

-- a section needs the term, and its term never changes
SELECT act('ad'); DELETE FROM enrollment_term;
SELECT act('sc');
SELECT expect_msg('a section before the term is set',
  $$INSERT INTO sections (program_id,name,year_level,capacity) VALUES ('00000000-0000-0000-0000-0000000000f8','Z',1,5)$$, 'not set');
SELECT act('ad'); INSERT INTO enrollment_term (school_year, semester) VALUES ('2026-2027','2nd');
SELECT act('sc');
SELECT expect_msg('change the term of a section',
  format($$UPDATE sections SET semester = '1st' WHERE id = %L$$, md5('ST18B')::uuid), 'cannot be changed');

-- a section made without a name takes the next letter
INSERT INTO sections (program_id,year_level,capacity) VALUES ('00000000-0000-0000-0000-0000000000f8',3,5);
INSERT INTO sections (program_id,year_level,capacity) VALUES ('00000000-0000-0000-0000-0000000000f8',3,5);
SELECT expect_eq('sections made without a name are A then B',
  (SELECT string_agg(name, ',' ORDER BY name) FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000f8' AND year_level = 3), 'A,B');

-- step 19: the grading scale, grade sheets, approval chain, changes and the INC lapse
-- (ST18B holds the student's 2nd semester subject T182, taught by pf18; the Dean's college matches)
SELECT act('pf18');
SELECT expect_msg('grades before the scale is set',
  format($$SELECT save_grades(%L, %L, '[]'::jsonb)$$, md5('ST18B')::uuid, md5('T182')::uuid), 'scale is not set');
SELECT act('ad');
SELECT expect_msg('overlapping bands are refused',
  $$SELECT save_grade_scale('[{"label":"Pass","outcome":"passed","from":1,"to":3},{"label":"Fail","outcome":"failed","from":3,"to":5}]'::jsonb, 14)$$, 'overlap');
SELECT act('dn');
SELECT expect_msg('the Dean cannot set the scale', $$SELECT save_grade_scale('[]'::jsonb, 14)$$, 'Only Admin');
SELECT act('ad');
SELECT save_grade_scale('[{"label":"Pass","outcome":"passed","from":1,"to":3},{"label":"Fail","outcome":"failed","from":5,"to":5},{"label":"INC","outcome":"incomplete"}]'::jsonb, 14);
SELECT expect_eq('2.5 resolves to passed', (SELECT r_outcome FROM resolve_grade('2.5')), 'passed');
SELECT expect_eq('5 resolves to failed', (SELECT r_outcome FROM resolve_grade('5')), 'failed');
SELECT expect_eq('inc resolves to incomplete', (SELECT r_outcome FROM resolve_grade('inc')), 'incomplete');
SELECT expect_eq('4 is not on the scale', (SELECT count(*)::text FROM resolve_grade('4')), '0');

SELECT act('pf');
SELECT expect_msg('another professor cannot enter grades',
  format($$SELECT save_grades(%L, %L, '[]'::jsonb)$$, md5('ST18B')::uuid, md5('T182')::uuid), 'Only the Professor of this subject');
SELECT act('pf18');
SELECT expect_msg('a grade off the scale is refused',
  format($$SELECT save_grades(%L, %L, (SELECT jsonb_agg(jsonb_build_object('studentId', ss.student_id, 'grade', '4')) FROM student_sections ss WHERE ss.section_id = %L))$$,
    md5('ST18B')::uuid, md5('T182')::uuid, md5('ST18B')::uuid), 'not on the grading scale');
SELECT save_grades(md5('ST18B')::uuid, md5('T182')::uuid,
  (SELECT jsonb_agg(jsonb_build_object('studentId', ss.student_id, 'grade', CASE WHEN ss.student_id = :'t18_student'::uuid THEN 'INC' ELSE '2.0' END))
     FROM student_sections ss WHERE ss.section_id = md5('ST18B')::uuid));
SELECT expect_eq('INC is saved as incomplete',
  (SELECT outcome FROM grades WHERE student_id = :'t18_student' AND subject_id = md5('T182')::uuid), 'incomplete');
SELECT expect_fail('a grade edited by hand', $$UPDATE grades SET grade_text = '1'$$);
SELECT act('dn');
SELECT expect_msg('the Dean cannot approve a draft',
  format($$SELECT approve_grades(%L, %L)$$, md5('ST18B')::uuid, md5('T182')::uuid), 'not waiting for approval');
SELECT act('pf18');
SELECT submit_grades(md5('ST18B')::uuid, md5('T182')::uuid);
SELECT expect_msg('submitted grades cannot be edited',
  format($$SELECT save_grades(%L, %L, '[]'::jsonb)$$, md5('ST18B')::uuid, md5('T182')::uuid), 'submitted');
SELECT act('dn');
SELECT approve_grades(md5('ST18B')::uuid, md5('T182')::uuid);
SELECT act('pf18');
SELECT expect_msg('approved grades cannot be edited',
  format($$SELECT save_grades(%L, %L, '[]'::jsonb)$$, md5('ST18B')::uuid, md5('T182')::uuid), 'approved');

-- an INC past the window lapses to a failed 5.0
SELECT set_config('app.grade_write', 'on', false);
UPDATE grades SET outcome_since = now() - interval '20 days' WHERE student_id = :'t18_student' AND subject_id = md5('T182')::uuid;
SELECT set_config('app.grade_write', 'off', false);
SELECT act('pf18');
SELECT expect_msg('a professor cannot run the lapse', $$SELECT lapse_incomplete_grades()$$, 'cannot run');
SELECT act('rg');
SELECT lapse_incomplete_grades();
SELECT expect_eq('the INC lapsed to a failed 5.0',
  (SELECT grade_text||'/'||outcome||'/'||lapsed::text FROM grades WHERE student_id = :'t18_student' AND subject_id = md5('T182')::uuid), '5.0/failed/true');

-- a grade change: the Professor proposes, the Dean signs, the Registrar approves
SELECT id AS t19_grade FROM grades WHERE student_id = :'t18_student' AND subject_id = md5('T182')::uuid \gset
SELECT act('pf18');
SELECT expect_msg('a change needs a reason', format($$SELECT propose_grade_change(%L, '2.5', '')$$, :'t19_grade'), 'reason');
SELECT propose_grade_change(:'t19_grade', '2.5', 'Recorded the wrong grade') AS t19_change \gset
SELECT expect_msg('only one change waits per grade', format($$SELECT propose_grade_change(%L, '2.0', 'Again')$$, :'t19_grade'), 'already waiting');
SELECT act('rg');
SELECT expect_msg('the Registrar cannot approve before the Dean signs', format($$SELECT approve_grade_change(%L)$$, :'t19_change'), 'not waiting for the Registrar');
SELECT act('dn');
SELECT sign_grade_change(:'t19_change');
SELECT expect_eq('the grade stays until the Registrar approves',
  (SELECT grade_text FROM grades WHERE id = :'t19_grade'), '5.0');
SELECT act('rg');
SELECT approve_grade_change(:'t19_change');
SELECT expect_eq('the approved change is applied',
  (SELECT grade_text||'/'||outcome||'/'||lapsed::text FROM grades WHERE id = :'t19_grade'), '2.5/passed/false');

-- ============================================================
-- prerequisites and credits (step 20), 20261026040000_prerequisites_and_credits.sql.
-- Uses the BST18 fixtures above: the student t18_student has a pass in T182 (through the grade
-- change) and nothing in T181. dn2 is the Dean of the other college (step 16). The extra subjects
-- are P20F (failed), P20I (incomplete), P20D (dropped), P20S (a pass in a sheet that is only
-- submitted, so it does not count), P20C (credit target) and four year 2 subjects, P20U1 to P20U4.
-- ============================================================
SELECT act('ad');
INSERT INTO subjects (id,program_id,code,title,units,year_level,semester) VALUES
  (md5('P20F')::uuid,'00000000-0000-0000-0000-0000000000f8','P20F','Failed one',3,1,'2nd'),
  (md5('P20I')::uuid,'00000000-0000-0000-0000-0000000000f8','P20I','Incomplete one',3,1,'2nd'),
  (md5('P20D')::uuid,'00000000-0000-0000-0000-0000000000f8','P20D','Dropped one',3,1,'2nd'),
  (md5('P20S')::uuid,'00000000-0000-0000-0000-0000000000f8','P20S','Submitted only',3,1,'2nd'),
  (md5('P20C')::uuid,'00000000-0000-0000-0000-0000000000f8','P20C','Credit target',3,1,'2nd'),
  (md5('P20U1')::uuid,'00000000-0000-0000-0000-0000000000f8','P20U1','Upper one',3,2,'1st'),
  (md5('P20U2')::uuid,'00000000-0000-0000-0000-0000000000f8','P20U2','Upper two',3,2,'1st'),
  (md5('P20U3')::uuid,'00000000-0000-0000-0000-0000000000f8','P20U3','Upper three',3,2,'1st'),
  (md5('P20U4')::uuid,'00000000-0000-0000-0000-0000000000f8','P20U4','Upper four',3,2,'1st');
INSERT INTO subjects (id,program_id,code,title,units) VALUES
  (md5('P20N')::uuid,'00000000-0000-0000-0000-0000000000f8','P20N','No year level',3);

-- the student's earlier results, written the way the grading functions would have left them
SELECT set_config('app.grade_write', 'on', false);
INSERT INTO grade_sheets (id,section_id,subject_id,school_year,semester,status) VALUES
  (md5('G20F')::uuid, md5('ST18B')::uuid, md5('P20F')::uuid, '2026-2027','2nd','approved'),
  (md5('G20I')::uuid, md5('ST18B')::uuid, md5('P20I')::uuid, '2026-2027','2nd','approved'),
  (md5('G20D')::uuid, md5('ST18B')::uuid, md5('P20D')::uuid, '2026-2027','2nd','approved'),
  (md5('G20S')::uuid, md5('ST18B')::uuid, md5('P20S')::uuid, '2026-2027','2nd','submitted');
INSERT INTO grades (sheet_id,section_id,subject_id,student_id,school_year,semester,grade_text,outcome) VALUES
  (md5('G20F')::uuid, md5('ST18B')::uuid, md5('P20F')::uuid, :'t18_student', '2026-2027','2nd','5.0','failed'),
  (md5('G20I')::uuid, md5('ST18B')::uuid, md5('P20I')::uuid, :'t18_student', '2026-2027','2nd','INC','incomplete'),
  (md5('G20D')::uuid, md5('ST18B')::uuid, md5('P20D')::uuid, :'t18_student', '2026-2027','2nd','DRP','dropped'),
  (md5('G20S')::uuid, md5('ST18B')::uuid, md5('P20S')::uuid, :'t18_student', '2026-2027','2nd','2.0','passed');
SELECT set_config('app.grade_write', 'off', false);

-- writes go only through the functions, Admin and superuser included
SELECT expect_msg('insert a prerequisite by hand',
  format($$INSERT INTO subject_prerequisites (subject_id, prerequisite_id) VALUES (%L, %L)$$, md5('P20U1')::uuid, md5('T182')::uuid), 'only through their functions');
SELECT expect_msg('insert a credit by hand',
  format($$INSERT INTO student_credits (student_id, subject_id, reason) VALUES (%L, %L, 'x')$$, :'t18_student', md5('P20C')::uuid), 'only through their functions');

-- nothing is required yet
SELECT expect_eq('a subject with no prerequisite is allowed',
  (subject_eligibility(:'t18_student', md5('T181')::uuid)->>'allowed'), 'true');

-- who may set prerequisites, and the refusals that name the subjects
SELECT act('rg');
SELECT expect_msg('the Registrar cannot set prerequisites',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20U1')::uuid, md5('T182')::uuid), 'Only Admin or the Dean');
SELECT act('sc');
SELECT expect_msg('the Secretary cannot set prerequisites',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20U1')::uuid, md5('T182')::uuid), 'Only Admin or the Dean');
SELECT act('dn2');
SELECT expect_msg('a Dean cannot set the prerequisites of another college',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20U1')::uuid, md5('T182')::uuid), 'Only the Dean of this college');
SELECT act('ad');
SELECT expect_msg('a subject cannot require itself',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20U1')::uuid, md5('P20U1')::uuid), 'cannot require itself');
SELECT expect_msg('a prerequisite in another program',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20U1')::uuid, md5('Y1')::uuid), 'another program');
SELECT expect_msg('a later subject cannot be a prerequisite',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('T181')::uuid, md5('P20U1')::uuid), 'not earlier in the curriculum');
SELECT expect_msg('the same year and semester is not earlier',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('T181')::uuid, md5('T183')::uuid), 'not earlier in the curriculum');
SELECT expect_msg('a subject with no year level',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20N')::uuid, md5('T181')::uuid), 'Set the year level');
SELECT expect_msg('an unknown required subject',
  format($$SELECT save_prerequisites(%L, ARRAY[%L]::uuid[])$$, md5('P20U1')::uuid, md5('nobody')::uuid), 'was not found');
SELECT expect_eq('the refusals wrote nothing', (SELECT count(*)::text FROM subject_prerequisites), '0');

-- Admin sets them; the whole list of a subject is replaced each time
SELECT save_prerequisites(md5('P20U1')::uuid, ARRAY[md5('T182')::uuid, md5('T181')::uuid]);
SELECT save_prerequisites(md5('P20U1')::uuid, ARRAY[md5('T182')::uuid]);
SELECT expect_eq('saving again replaces the list', (SELECT string_agg(r.code, ',') FROM subject_prerequisites sp JOIN subjects r ON r.id = sp.prerequisite_id WHERE sp.subject_id = md5('P20U1')::uuid), 'T182');
SELECT save_prerequisites(md5('P20U2')::uuid, ARRAY[md5('T181')::uuid]);
SELECT save_prerequisites(md5('P20U3')::uuid, ARRAY[md5('P20F')::uuid, md5('P20I')::uuid, md5('P20D')::uuid, md5('P20S')::uuid]);
-- the Dean of the college sets the fourth
SELECT act('dn');
SELECT save_prerequisites(md5('P20U4')::uuid, ARRAY[md5('P20C')::uuid]);
SELECT expect_eq('prerequisites are set: 1 + 1 + 4 + 1 rows', (SELECT count(*)::text FROM subject_prerequisites), '7');

-- eligibility: one definition, names every blocking prerequisite
SELECT expect_eq('a passed prerequisite unblocks',
  (subject_eligibility(:'t18_student', md5('P20U1')::uuid)->>'allowed'), 'true');
SELECT expect_eq('a prerequisite never taken blocks and is named',
  (SELECT (subject_eligibility(:'t18_student', md5('P20U2')::uuid)->>'allowed')||'/'||(subject_eligibility(:'t18_student', md5('P20U2')::uuid)->'blockedBy'->0->>'code')||'/'||(subject_eligibility(:'t18_student', md5('P20U2')::uuid)->'blockedBy'->0->>'status')),
  'false/T181/not_taken');
SELECT expect_eq('failed, incomplete, dropped and a pass in an unapproved sheet all block',
  (SELECT string_agg((b->>'code')||':'||(b->>'status'), ',' ORDER BY b->>'code') FROM jsonb_array_elements(subject_eligibility(:'t18_student', md5('P20U3')::uuid)->'blockedBy') b),
  'P20D:dropped,P20F:failed,P20I:incomplete,P20S:not_taken');
SELECT act('sc');
SELECT expect_eq('the Secretary of the college can check eligibility',
  (subject_eligibility(:'t18_student', md5('P20U1')::uuid)->>'allowed'), 'true');
SELECT act('dn2');
SELECT expect_msg('a Dean of another college cannot check a student', format($$SELECT subject_eligibility(%L, %L)$$, :'t18_student', md5('P20U1')::uuid), 'not in your college');
SELECT act('pf');
SELECT expect_msg('a Professor cannot check eligibility', format($$SELECT subject_eligibility(%L, %L)$$, :'t18_student', md5('P20U1')::uuid), 'cannot check eligibility');
SELECT act('ad');
SELECT expect_msg('eligibility for an unknown subject', format($$SELECT subject_eligibility(%L, %L)$$, :'t18_student', md5('nobody')::uuid), 'subject was not found');

-- a passing retake unblocks: a second attempt of P20F, in another section, approved and passed
SELECT set_config('app.grade_write', 'on', false);
INSERT INTO grade_sheets (id,section_id,subject_id,school_year,semester,status) VALUES
  (md5('G20R')::uuid, md5('ST18A')::uuid, md5('P20F')::uuid, '2026-2027','1st','approved');
INSERT INTO grades (sheet_id,section_id,subject_id,student_id,school_year,semester,grade_text,outcome) VALUES
  (md5('G20R')::uuid, md5('ST18A')::uuid, md5('P20F')::uuid, :'t18_student', '2026-2027','1st','2.5','passed');
SELECT set_config('app.grade_write', 'off', false);
SELECT expect_eq('a passing retake unblocks the subject that needed it',
  (SELECT string_agg(b->>'code', ',' ORDER BY b->>'code') FROM jsonb_array_elements(subject_eligibility(:'t18_student', md5('P20U3')::uuid)->'blockedBy') b),
  'P20D,P20I,P20S');

-- credits: the Dean or the Secretary records, the Registrar approves
SELECT act('rg');
SELECT expect_msg('the Registrar cannot record a credit',
  format($$SELECT record_credit(%L, %L, 'TOR line 1')$$, :'t18_student', md5('P20C')::uuid), 'Only the Dean or the College Secretary');
SELECT act('dn2');
SELECT expect_msg('a Dean of another college cannot record a credit',
  format($$SELECT record_credit(%L, %L, 'TOR line 1')$$, :'t18_student', md5('P20C')::uuid), 'not in your college');
SELECT act('dn');
SELECT expect_msg('a credit needs a reason',
  format($$SELECT record_credit(%L, %L, '   ')$$, :'t18_student', md5('P20C')::uuid), 'Enter the reason');
SELECT expect_msg('a reason over 500 characters',
  format($$SELECT record_credit(%L, %L, %L)$$, :'t18_student', md5('P20C')::uuid, repeat('x', 501)), 'longer than 500');
SELECT expect_msg('a credit for a subject of another program',
  format($$SELECT record_credit(%L, %L, 'TOR line 1')$$, :'t18_student', md5('Y1')::uuid), 'not in the student''s program');
SELECT expect_msg('a credit for a subject already passed',
  format($$SELECT record_credit(%L, %L, 'TOR line 1')$$, :'t18_student', md5('T182')::uuid), 'already passed or been credited');
SELECT record_credit(:'t18_student', md5('P20C')::uuid, 'TOR page 2, line 5') AS t20_credit \gset
SELECT expect_msg('a credit already waiting',
  format($$SELECT record_credit(%L, %L, 'Again')$$, :'t18_student', md5('P20C')::uuid), 'already waiting for the Registrar');
SELECT expect_eq('a credit waiting for the Registrar does not count',
  (subject_eligibility(:'t18_student', md5('P20U4')::uuid)->>'allowed'), 'false');
SELECT expect_msg('the Dean cannot approve a credit', format($$SELECT approve_credit(%L)$$, :'t20_credit'), 'Only the Registrar can approve');
SELECT expect_msg('the Dean cannot read the credits waiting', $$SELECT credits_pending()$$, 'cannot read credits waiting');
SELECT act('rg');
SELECT expect_eq('the Registrar sees the credit waiting', (SELECT jsonb_array_length(credits_pending())::text), '1');
SELECT approve_credit(:'t20_credit');
SELECT expect_msg('a credit approved twice', format($$SELECT approve_credit(%L)$$, :'t20_credit'), 'not waiting for approval');
SELECT expect_eq('an approved credit counts as a pass',
  (subject_eligibility(:'t18_student', md5('P20U4')::uuid)->>'allowed'), 'true');
SELECT expect_eq('the approval is audited with the Registrar',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'student_credits' AND action = 'UPDATE' AND actor_id = md5('rg')::uuid AND new_data->>'status' = 'approved'), '1');

-- a rejected credit needs a reason, does not count, and can be recorded again
SELECT act('sc');
SELECT record_credit(:'t18_student', md5('P20S')::uuid, 'TOR page 3, line 2') AS t20_credit2 \gset
SELECT act('rg');
SELECT expect_msg('a rejection needs a reason', format($$SELECT reject_credit(%L, '')$$, :'t20_credit2'), 'Enter the reason');
SELECT reject_credit(:'t20_credit2', 'The TOR line is a different subject');
SELECT expect_eq('the rejected credit keeps its reason',
  (SELECT status||'/'||rejected_reason FROM student_credits WHERE id = :'t20_credit2'), 'rejected/The TOR line is a different subject');
SELECT expect_eq('a rejected credit does not count',
  (SELECT string_agg(b->>'code', ',' ORDER BY b->>'code') FROM jsonb_array_elements(subject_eligibility(:'t18_student', md5('P20U3')::uuid)->'blockedBy') b),
  'P20D,P20I,P20S');
SELECT act('sc');
SELECT record_credit(:'t18_student', md5('P20S')::uuid, 'TOR page 3, line 4');
SELECT expect_eq('a rejected credit can be recorded again (one rejected, one waiting)',
  (SELECT string_agg(status, ',' ORDER BY status) FROM student_credits WHERE student_id = :'t18_student' AND subject_id = md5('P20S')::uuid), 'pending,rejected');

-- what the credits window and the Prerequisites page read
SELECT act('dn');
SELECT expect_eq('the credit window lists the credits of the student', (SELECT jsonb_array_length(credit_overview(:'t18_student')->'credits')::text), '3');
SELECT expect_eq('the options leave out a credited subject and one with a credit waiting',
  (SELECT count(*)::text FROM jsonb_array_elements(credit_overview(:'t18_student')->'options') o WHERE o->>'code' IN ('T182','P20C','P20S')), '0');
SELECT expect_eq('the options keep a subject never taken',
  (SELECT count(*)::text FROM jsonb_array_elements(credit_overview(:'t18_student')->'options') o WHERE o->>'code' = 'T181'), '1');
SELECT act('dn2');
SELECT expect_msg('another college cannot read the credits', format($$SELECT credit_overview(%L)$$, :'t18_student'), 'not in your college');
SELECT act('pf');
SELECT expect_msg('a Professor cannot read credits', format($$SELECT credit_overview(%L)$$, :'t18_student'), 'cannot read credits');
SELECT expect_msg('a Professor cannot read prerequisites', $$SELECT prerequisite_programs()$$, 'cannot read prerequisites');
SELECT act('dn');
SELECT expect_eq('the Dean sees the programs of the own college',
  (jsonb_array_length(prerequisite_programs())::text), (SELECT count(*)::text FROM programs WHERE college_id = '00000000-0000-0000-0000-0000000000c1'));
SELECT act('dn2');
SELECT expect_eq('the other Dean sees only the programs of the other college',
  (jsonb_array_length(prerequisite_programs())::text), (SELECT count(*)::text FROM programs WHERE college_id = '00000000-0000-0000-0000-0000000000c2'));
SELECT expect_msg('the other Dean cannot open the program', $$SELECT prerequisites_list('00000000-0000-0000-0000-0000000000f8')$$, 'not in your college');
SELECT act('rg');
SELECT expect_eq('the Registrar sees every program',
  (jsonb_array_length(prerequisite_programs())::text), (SELECT count(*)::text FROM programs));
SELECT expect_eq('the program list shows the prerequisites of a subject',
  (SELECT jsonb_array_length(x->'prerequisites')::text FROM jsonb_array_elements(prerequisites_list('00000000-0000-0000-0000-0000000000f8')) x WHERE x->>'code' = 'P20U3'), '4');

-- deleting a subject
SELECT act('ad');
SELECT expect_msg('delete a subject that others require', format($$DELETE FROM subjects WHERE id = %L$$, md5('T182')::uuid), 'is a prerequisite of');
SELECT expect_msg('the refusal names the subject that requires it', format($$DELETE FROM subjects WHERE id = %L$$, md5('T182')::uuid), 'P20U1');
SELECT expect_eq('the refused delete changed nothing', (SELECT count(*)::text FROM subject_prerequisites WHERE prerequisite_id = md5('T182')::uuid), '1');
DELETE FROM subjects WHERE id = md5('P20U2')::uuid;
SELECT expect_eq('a subject nobody requires can be deleted, and its own prerequisites go with it',
  (SELECT (SELECT count(*) FROM subjects WHERE id = md5('P20U2')::uuid)::text||'/'||(SELECT count(*) FROM subject_prerequisites WHERE subject_id = md5('P20U2')::uuid)::text), '0/0');

-- audit: every change has its actor
SELECT expect_eq('the Dean''s prerequisite is audited',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'subject_prerequisites' AND action = 'INSERT' AND actor_id = md5('dn')::uuid), '1');
SELECT expect_eq('the credits are audited',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'student_credits' AND action = 'INSERT'), '3');

-- the signed-in role can call the checks, not the internal helpers, and cannot write the tables
\if :has_auth
SET ROLE authenticated;
SELECT act('dn');
SELECT expect_eq('authenticated Dean checks eligibility', (subject_eligibility(:'t18_student', md5('P20U1')::uuid)->>'allowed'), 'true');
SELECT expect_fail('authenticated calls student_has_passed', format($$SELECT student_has_passed(%L, %L)$$, :'t18_student', md5('T182')::uuid));
SELECT expect_fail('authenticated calls student_blocking_prerequisites', format($$SELECT * FROM student_blocking_prerequisites(%L, %L)$$, :'t18_student', md5('P20U1')::uuid));
SELECT expect_fail('authenticated writes a prerequisite directly',
  format($$INSERT INTO subject_prerequisites (subject_id, prerequisite_id) VALUES (%L, %L)$$, md5('P20U1')::uuid, md5('T181')::uuid));
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 20 grant checks not run';
\endif

-- a withdrawal releases the current enrollment only; the earlier term stays as history
SELECT act('rg');
SELECT withdraw_applicant(md5('At1')::uuid, 'Step 18 check');
SELECT expect_eq('only the current enrollment was released',
  (SELECT string_agg(semester, ',' ORDER BY semester) FROM student_sections WHERE student_id = :'t18_student'), '1st');
SELECT expect_eq('the CORs of both terms stay as history', (SELECT count(*)::text FROM cors WHERE student_id = :'t18_student'), '2');

-- ============================================================
-- close term (step 21), 20261026050000_close_term.sql.
-- Own program BST21, in a term no other fixture uses (2030-2031), so closing it sees only these
-- students. Subjects: S211 and S212 (year 1, 1st) and S213 (year 1, 2nd), so year 1 is the last
-- year and its 2nd semester the last semester. Four students in section A: q21a passes everything,
-- q21b has an INC, q21c fails S211, q21d withdraws before the term is closed. dn2 is the Dean of
-- the other college (step 16). The grading scale of step 19 is saved again so this block stands alone.
-- ============================================================
SELECT act('ad');
UPDATE enrollment_term SET school_year = '2030-2031', semester = '1st';
SELECT save_grade_scale('[{"label":"Pass","outcome":"passed","from":1,"to":3},{"label":"Fail","outcome":"failed","from":5,"to":5},{"label":"INC","outcome":"incomplete"}]'::jsonb, 14);
INSERT INTO programs (id,code,name,college_id) VALUES ('00000000-0000-0000-0000-0000000000f9','BST21','Test Program T21','00000000-0000-0000-0000-0000000000c1');
INSERT INTO subjects (id,program_id,code,title,units,year_level,semester) VALUES
  (md5('S211')::uuid,'00000000-0000-0000-0000-0000000000f9','S211','S one',3,1,'1st'),
  (md5('S212')::uuid,'00000000-0000-0000-0000-0000000000f9','S212','S two',3,1,'1st'),
  (md5('S213')::uuid,'00000000-0000-0000-0000-0000000000f9','S213','S three',3,1,'2nd');
SELECT mk_applicant('q21a','00000000-0000-0000-0000-0000000000f9', mnl_today());
SELECT mk_applicant('q21b','00000000-0000-0000-0000-0000000000f9', mnl_today());
SELECT mk_applicant('q21c','00000000-0000-0000-0000-0000000000f9', mnl_today());
SELECT mk_applicant('q21d','00000000-0000-0000-0000-0000000000f9', mnl_today());
SELECT act('sc');
INSERT INTO sections (id,program_id,name,year_level,capacity) VALUES (md5('SC21A')::uuid,'00000000-0000-0000-0000-0000000000f9','A',1,5);
SELECT act('rg');
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Aq21a')::uuid,'x',md5('rg')::uuid);
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Aq21b')::uuid,'x',md5('rg')::uuid);
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Aq21c')::uuid,'x',md5('rg')::uuid);
INSERT INTO students (applicant_id,student_number,documents_received_by) VALUES (md5('Aq21d')::uuid,'x',md5('rg')::uuid);
SELECT id AS t21_a FROM students WHERE applicant_id = md5('Aq21a')::uuid \gset
SELECT id AS t21_b FROM students WHERE applicant_id = md5('Aq21b')::uuid \gset
SELECT id AS t21_c FROM students WHERE applicant_id = md5('Aq21c')::uuid \gset
SELECT id AS t21_d FROM students WHERE applicant_id = md5('Aq21d')::uuid \gset
SELECT expect_eq('the four students are in section A of the term',
  (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SC21A')::uuid), '4');
SELECT withdraw_applicant(md5('Aq21d')::uuid, 'Step 21 check');
SELECT expect_eq('the withdrawn student left the section',
  (SELECT count(*)::text FROM student_sections WHERE section_id = md5('SC21A')::uuid), '3');

-- nothing can be closed before every section subject with students has Dean-approved grades
SELECT act('sc');
SELECT expect_msg('a Secretary cannot close the term', $$SELECT close_term()$$, 'Only the Registrar');
SELECT expect_msg('a Secretary cannot read the term status', $$SELECT term_close_status()$$, 'Only the Registrar');
SELECT act('rg');
SELECT expect_eq('the status lists both section subjects as missing', (term_close_status()->>'missingTotal'), '2');
SELECT expect_msg('close with no grades', $$SELECT close_term()$$, 'Grades are not approved yet for: BST21 1A S211, BST21 1A S212');

SELECT act('ad');
SELECT save_grades(md5('SC21A')::uuid, md5('S211')::uuid, jsonb_build_array(
  jsonb_build_object('studentId', :'t21_a'::uuid, 'grade', '2.0'),
  jsonb_build_object('studentId', :'t21_b'::uuid, 'grade', '2.0'),
  jsonb_build_object('studentId', :'t21_c'::uuid, 'grade', '5')));
SELECT submit_grades(md5('SC21A')::uuid, md5('S211')::uuid);
SELECT approve_grades(md5('SC21A')::uuid, md5('S211')::uuid);
SELECT act('rg');
SELECT expect_eq('one section subject is still missing', (term_close_status()->>'missingTotal'), '1');
SELECT expect_msg('close with one sheet missing', $$SELECT close_term()$$, 'Grades are not approved yet for: BST21 1A S212');

SELECT act('ad');
SELECT save_grades(md5('SC21A')::uuid, md5('S212')::uuid, jsonb_build_array(
  jsonb_build_object('studentId', :'t21_a'::uuid, 'grade', '1.5'),
  jsonb_build_object('studentId', :'t21_b'::uuid, 'grade', 'INC'),
  jsonb_build_object('studentId', :'t21_c'::uuid, 'grade', '2.0')));
SELECT submit_grades(md5('SC21A')::uuid, md5('S212')::uuid);
SELECT approve_grades(md5('SC21A')::uuid, md5('S212')::uuid);

-- closing decides each student
SELECT act('rg');
SELECT expect_eq('nothing is missing now', (term_close_status()->>'missingTotal'), '0');
SELECT close_term()::text AS t21_summary \gset
SELECT expect_eq('one promoted, two to review, none completed',
  ((:'t21_summary'::jsonb->>'promote')||'/'||(:'t21_summary'::jsonb->>'review')||'/'||(:'t21_summary'::jsonb->>'completed')), '1/2/0');
SELECT expect_eq('the student who passed everything is marked promote',
  (SELECT result FROM term_results WHERE student_id = :'t21_a' AND school_year = '2030-2031' AND semester = '1st'), 'promote');
SELECT expect_eq('the incomplete is named in the reason',
  (SELECT result||': '||reason FROM term_results WHERE student_id = :'t21_b'), 'review: Incomplete in S212');
SELECT expect_eq('the failed subject is named in the reason',
  (SELECT result||': '||reason FROM term_results WHERE student_id = :'t21_c'), 'review: Failed S211');
SELECT expect_eq('the withdrawn student has no result', (SELECT count(*)::text FROM term_results WHERE student_id = :'t21_d'), '0');
SELECT expect_msg('close twice', $$SELECT close_term()$$, 'already closed');
SELECT expect_eq('the status says closed', (term_close_status()->>'closed'), 'true');
SELECT expect_msg('write a term result by hand',
  format($$INSERT INTO term_results (school_year, semester, student_id, program_id, year_level, section_name, result) VALUES ('2030-2031','1st',%L,'00000000-0000-0000-0000-0000000000f9',1,'A','promote')$$, :'t21_d'),
  'only through closing a term');

-- the review list: own college only, with the reason; the Registrar does not read it
SELECT act('sc');
SELECT expect_eq('the Secretary sees the two students of the college',
  (SELECT string_agg((x->>'studentId')::text, ',' ORDER BY x->>'studentNumber') FROM jsonb_array_elements(review_students()) x WHERE x->>'programCode' = 'BST21'),
  (SELECT string_agg(id::text, ',' ORDER BY student_number) FROM students WHERE id IN (:'t21_b'::uuid, :'t21_c'::uuid)));
SELECT act('dn2');
SELECT expect_eq('the Dean of the other college sees none',
  (SELECT count(*)::text FROM jsonb_array_elements(review_students()) x WHERE x->>'programCode' = 'BST21'), '0');
SELECT act('rg');
SELECT expect_msg('the Registrar cannot read the review list', $$SELECT review_students()$$, 'cannot read the review list');

-- the student's own card says to see the college, and shows no grade
SELECT act('q21b');
SELECT expect_eq('the student on review is sent to the college', my_needs_advising()::text, 'true');
SELECT act('q21a');
SELECT expect_eq('the student who passed everything is not', my_needs_advising()::text, 'false');

-- opening the next term copies the sections and seats the promoted student
SELECT act('ad');
UPDATE enrollment_term SET semester = '2nd';
SELECT expect_eq('the 2nd semester has the copied section with its capacity',
  (SELECT string_agg(name||year_level::text||':'||capacity::text, ',') FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000f9' AND school_year = '2030-2031' AND semester = '2nd'), 'A1:5');
SELECT expect_eq('the new section holds the subjects of the 2nd semester only',
  (SELECT string_agg(DISTINCT sub.code, ',') FROM section_subjects x JOIN sections sec ON sec.id = x.section_id JOIN subjects sub ON sub.id = x.subject_id
    WHERE sec.program_id = '00000000-0000-0000-0000-0000000000f9' AND sec.semester = '2nd'), 'S213');
SELECT expect_eq('the promoted student is seated in section A of the 2nd semester',
  (SELECT count(*)::text FROM student_sections ss JOIN sections sec ON sec.id = ss.section_id
    WHERE ss.student_id = :'t21_a' AND ss.semester = '2nd' AND sec.name = 'A' AND sec.year_level = 1), '1');
SELECT expect_eq('the promoted student was told',
  (SELECT count(*)::text FROM notifications WHERE user_id = md5('q21a')::uuid AND kind = 'section_placed' AND message LIKE '%2nd semester of school year 2030-2031%'), '1');
SELECT expect_eq('a student on review is not seated',
  (SELECT count(*)::text FROM student_sections WHERE student_id IN (:'t21_b'::uuid, :'t21_c'::uuid) AND semester = '2nd'), '0');
SELECT expect_eq('the closed term records that it was opened',
  (SELECT (opened_at IS NOT NULL)::text FROM term_closures WHERE school_year = '2030-2031' AND semester = '1st'), 'true');
-- a term change back and forth places nobody twice
UPDATE enrollment_term SET semester = 'summer';
UPDATE enrollment_term SET semester = '2nd';
SELECT expect_eq('the promoted student has one enrollment in the 2nd semester',
  (SELECT count(*)::text FROM student_sections WHERE student_id = :'t21_a' AND semester = '2nd'), '1');
SELECT expect_eq('the review list still has both students after the term opened',
  (SELECT count(*)::text FROM jsonb_array_elements(review_students()) x WHERE x->>'programCode' = 'BST21'), '2');

-- placing a student of the review list takes them off it
SELECT act('sc');
SELECT move_student_section(:'t21_c', (SELECT id FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000f9' AND semester = '2nd' AND name = 'A'));
SELECT expect_eq('a placed student leaves the review list',
  (SELECT count(*)::text FROM jsonb_array_elements(review_students()) x WHERE x->>'programCode' = 'BST21'), '1');
SELECT act('q21c');
SELECT expect_eq('and is no longer told to see the college', my_needs_advising()::text, 'false');

-- the last semester of the last year: passing it completes the program
SELECT act('ad');
SELECT id AS t21_sec2 FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000f9' AND semester = '2nd' AND name = 'A' \gset
SELECT save_grades(:'t21_sec2'::uuid, md5('S213')::uuid, jsonb_build_array(
  jsonb_build_object('studentId', :'t21_a'::uuid, 'grade', '2.0'),
  jsonb_build_object('studentId', :'t21_c'::uuid, 'grade', '2.5')));
SELECT submit_grades(:'t21_sec2'::uuid, md5('S213')::uuid);
SELECT approve_grades(:'t21_sec2'::uuid, md5('S213')::uuid);
SELECT act('rg');
SELECT close_term()::text AS t21_summary2 \gset
SELECT expect_eq('both students completed the program',
  ((:'t21_summary2'::jsonb->>'promote')||'/'||(:'t21_summary2'::jsonb->>'review')||'/'||(:'t21_summary2'::jsonb->>'completed')), '0/0/2');
SELECT expect_eq('the Registrar sees them in the completed list',
  (SELECT count(*)::text FROM jsonb_array_elements(completed_students()) x WHERE x->>'programCode' = 'BST21'), '2');
SELECT act('sc');
SELECT expect_msg('a Secretary cannot read the completed list', $$SELECT completed_students()$$, 'Only the Registrar');

-- the next school year: year 1 sections are copied for new students, nobody is promoted past the last year
SELECT act('ad');
UPDATE enrollment_term SET school_year = '2031-2032', semester = '1st';
SELECT expect_eq('the next school year copies the year 1 section only',
  (SELECT string_agg(name||year_level::text, ',') FROM sections WHERE program_id = '00000000-0000-0000-0000-0000000000f9' AND school_year = '2031-2032' AND semester = '1st'), 'A1');
SELECT expect_eq('a completed student is not seated again',
  (SELECT count(*)::text FROM student_sections WHERE student_id = :'t21_a' AND school_year = '2031-2032'), '0');

-- audit and grants
SELECT expect_eq('both closings are audited with their actor',
  (SELECT count(*)::text FROM audit_log WHERE table_name = 'term_closures' AND action = 'INSERT' AND actor_id = md5('rg')::uuid), '2');
\if :has_auth
SET ROLE authenticated;
SELECT act('rg');
SELECT expect_eq('authenticated Registrar reads the term status', (term_close_status()->'term'->>'semester'), '1st');
SELECT expect_fail('authenticated calls open_term', $$SELECT open_term('2030-2031', '2nd')$$);
SELECT expect_fail('authenticated calls term_missing_sheets', $$SELECT * FROM term_missing_sheets()$$);
SELECT expect_fail('authenticated writes a term result directly',
  format($$INSERT INTO term_results (school_year, semester, student_id, program_id, year_level, section_name, result) VALUES ('2030-2031','1st',%L,'00000000-0000-0000-0000-0000000000f9',1,'A','promote')$$, :'t21_d'));
RESET ROLE;
\else
SELECT 'skipped: no authenticated role, step 21 grant checks not run';
\endif

-- audit
SELECT 'audit rows', count(*), count(DISTINCT table_name) AS tables FROM audit_log;
SELECT 'toggle audited', actor_role, old_data->>'payment_required' AS was, new_data->>'payment_required' AS now FROM audit_log WHERE table_name='program_payment_settings';
SELECT expect_fail('edit audit log', $$UPDATE audit_log SET reason='x'$$);
SELECT expect_fail('delete audit log', $$DELETE FROM audit_log$$);
