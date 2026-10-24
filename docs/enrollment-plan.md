# Enrollment System Plan (after Admissions)

Status: plan only, nothing built yet.

## Who uses it?
1. Admitted applicants from the admission system
2. Students (an applicant is promoted to student once the Registrar receives their documents)
3. Registrar
4. Finance
5. Dean
6. College Secretary (the Dean's assistant)
7. Professors (assigned to subjects)
8. Admin

Also found at PLP, not in this system for now:
- Admissions Officer (signs the endorsement slip, admissions side)
- Student Success Office

## What is the goal of the enrollment system after admissions?
- Assign the student ID automatically and finalize the enrollment (the COR)

## Scope
- Newly admitted students only, for now. Returning students come later.
- The enrollment slip belongs to the Admissions side, not this system.
- This system produces two documents:
  - Assessment slip: the light version. Issued by the Registrar.
  - COR: the finalized version.

## The process
Based on the PLP Registrar's 2024 Citizen's Charter, adjusted to our decisions.

1. Applicant confirms in Admissions. Admissions sends their details to Enrollment with one secure call (see Connection to PLP Admissions). The two databases stay separate.
2. Staff set up the visit schedule per program. The student never picks a slot. They are told when and where to go, they visit, and they get served.
3. Registrar receives the original documents and marks them received. The system then assigns the student number automatically. The applicant is now a student.
4. The College Secretary prepares the schedule: sections, professors for each subject, and rooms. The Dean reviews and signs off the professor loading, then the schedule goes to the Registrar for approval. (The Dean can also do everything the Secretary does.)
5. Registrar approves and issues the assessment slip.
6. Finance clears payment, only if the student's course requires payment (see the toggle below).
7. Registrar issues the COR. The student is enrolled.

## Connection to PLP Admissions
Enrollment receives its applicants from the PLP Admissions system. The two systems keep their own databases and their own logins. They only talk through one secure web call (HTTPS) from Admissions to Enrollment.

How it works:
1. The applicant clicks Confirm enrollment in Admissions. Admissions sends their details to Enrollment right away.
2. Enrollment checks the shared secret and the details. If they are good, it creates the Applicant account and the applicant sees their first "Your next step" card.
3. The applicant gets an email with a link to set their own password. No password ever travels between the two systems.

What Admissions sends:
- Applicant reference (for example ADM-2026-000042). It never changes and it is how duplicates are caught.
- Full name and email
- Approved program
- Admission date
- Admission type: new student or transferee
- Source name: PLP Admissions

Rules:
- Same applicant sent twice: still one account. Details are refreshed while they are an applicant, and nothing changes once they are a student.
- Programs: Enrollment uses the same program codes as Admissions (all 13 courses, including each BSED major), so nothing is lost or mapped wrongly. A course Enrollment does not have is rejected with a clear message. Today BSENT has no match in the existing system, so this system must include it.
- If Enrollment is down: Admissions keeps the send pending, never blocks the student's confirmation, and staff can retry with a Send to Enrollment button.
- The shared secret lives only in the hosting settings of both systems, never in the code.
- Enrollment records every request it receives, successful or failed, with who sent it and when.
- Admin can see every received request, resend a failed one, and switch the connection on or off.
- Later, optional: Enrollment tells Admissions when the student is enrolled.

## Reschedules
Two ways a visit date can move. In both, the student never picks a new slot. The system or staff do.

1. Mass reschedule (typhoon, class suspension, office closure)
   - A higher up (Registrar or Admin) picks the affected date, and optionally the program or office, and gives a reason.
   - Every student booked on that date is moved automatically to the next available slot, or to a new date that staff set.
   - Moved students are told on their "Your next step" card and by email, with the new date, place and what to bring.
   - Nobody loses their place or counts as a no-show because of it.
2. Student request (emergency, illness, family)
   - The student sends a reschedule request from their next step card, with a reason. The student cannot move themselves.
   - The Registrar reviews it. If a slot is available, they approve it and the student is moved. If not, they decline with a note or offer the next available date.
   - The student sees the answer on their card and by email.

Rules for both:
- A reschedule moves the visit date only. The student's progress, student number and documents stay as they are.
- Every reschedule is written to the audit log: who, what, when, why.

## Access (RBAC)
Rule: everyone sees only what they need to do their job. Deny by default. The limits are enforced in the database, not just hidden in the screens, so typing a link by hand does not open anything extra.

| Role | Can see | Can do | Cannot see |
|---|---|---|---|
| Applicant | Only their own status and next step | Nothing in enrollment yet | Anyone else, any staff pages |
| Student | Only their own record, assessment slip, COR, schedule, next step | View and download their own documents, request a reschedule | Anyone else, payment settings |
| Registrar | All students' enrollment records and submitted documents | Mark documents received, approve schedules, issue the assessment slip and COR, approve or decline reschedule requests, set a mass reschedule | Payment settings (view only), user management |
| Finance | Payment status and amounts due | Record payment, change the payment toggle | Uploaded documents, schedules |
| Dean | Their own college's students, schedules and professor loading | Sign off professor loading, do everything the College Secretary does | Other colleges, payment settings (view only) |
| College Secretary | Their own college's students and schedules | Prepare schedules, assign professors and rooms, advise | Other colleges, documents, payments, sign-off |
| Professor | Their assigned subjects and class lists (name and student number only) | View their own load | Documents, payments, other professors' classes |
| Admin | Everything | Everything any other role can do, plus manage accounts and roles, settings, the payment toggle, mass reschedules, and the Admissions connection | Nothing |

Other rules:
- Uploaded documents (birth certificate, report card, IDs) are visible to the Registrar and Admin only.
- Admin has full access, so every Admin action is written to the audit log like everyone else's, and each Admin uses their own account, never a shared one.
- A staff member sees only their own office's data. Dean and College Secretary are limited to one college.
- Every change to money settings, schedules and student numbers is written to an audit log: who, what, when.
- Passwords and secrets never appear on any screen. Staff accounts are created by Admin only.

## Considerations
- Payment is customizable per course. A toggle on each course says whether payment is required (for example Psychology, because it is a new program). If it is off, the Finance step is skipped.
- The College Secretary prepares the schedule and the Dean signs off, then it goes to the Registrar for approval
- Professors are assigned to subjects by the College Secretary, with the Dean's sign-off
- Generate the assessment slip and the COR
- Room slot assignment and scheduling
- Reschedules: a mass reschedule by a higher up (typhoon, suspension) and student requested ones (emergency), see the Reschedules section
- Every page ends with a "Your next step" card that tells the user where to go: the office, the window, the time, and what to bring (for example where to get the assessment slip or the COR, or what to bring to the Registrar)

## Decided
- Admin: does all things. It has every permission of every other role (your decision).
- Connection: this system receives its applicants from the PLP Admissions system through one secure web call, with separate databases (see Connection to PLP Admissions).
- Payment: a per-course toggle. Admin can change it (your decision). Finance can also change it (my recommendation from PLP, see below). The Registrar and the Dean can see it but not change it. Every change is recorded.
- Dean: still needed. The Dean has the sign-off on professor loading, and can do everything the College Secretary does.
- Dean sign-off: required before the schedule reaches the Registrar, because that matches PLP.
- College Secretary: the Dean's assistant. Does the day-to-day work: advising, preparing the schedule, assigning professors to subjects.
- Payment order: Finance comes after the assessment slip and before the COR
- Student number: assigned automatically by the system when the Registrar marks the documents received. Nobody types it. One number per student, never reused, and it cannot be edited afterward.
- Access: role based access control (RBAC), see the Access section above
- Enrollment slip: Admissions side, not here
- Visit slots: set up by staff, never by the student. A student can only request a reschedule.
- Reschedules: the Registrar and Admin can set a mass reschedule (my recommendation). The Registrar approves or declines student requests (my recommendation, because the Registrar runs the visits).
- Scope: newly admitted students first
- Real applicants or school project: does not matter

## What PLP does (the reason for the recommendations)
- Payment order: in the PLP Registrar's 2024 Citizen's Charter, the Dean advises and issues the assessment slip first. Finance then collects fees and tags the payment. The Registrar prints the COR last.
- The charter lists no fees and no Finance step for new students, which is why the payment toggle is needed for cases like Psychology.
- Who handles fees: Finance collects the fees, tags the payment, and the cashier issues the receipt. The Registrar only assesses fees for document requests and passes them to Finance. For incoming AB Psychology freshmen, the college charter has the Student Success Office provide the official list of qualifiers, the Dean or College Secretary print the tuition fee assessment, and Finance collect. That is why Finance, not the Registrar, should own the toggle alongside Admin.
- Older source, lower confidence: a school directory page says the admission fee is free except for the new AB Psychology program, and that PLP tuition is covered by the UniFAST free tuition law.
- Dean versus College Secretary: in the PLP College of Education charter, faculty loading is reviewed and signed by the College Dean, and subject loading per course, program, year and section is handled by the College Secretary. In the newer college charters (Business Administration, Hospitality, Early Childhood, Nursing and others), the College Secretary appears throughout the enrollment steps: academic advising and issuing the assessment slip. The 2024 Registrar charter still names the College Dean for those steps. Conclusion: the Secretary does the hands-on work, the Dean signs off. The Dean cannot be dropped, because of the sign-off.
- Confidence: the newer college charters were only readable in fragments, so exact wording per college may differ.
- Difference: in the charter the Dean issues the assessment slip. We decided the Registrar issues it.
