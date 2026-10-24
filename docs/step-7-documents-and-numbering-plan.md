# Plan: Step 7, Documents and student numbering (plp-enrollment)

Status: **built, not yet run.** Decisions A, B and C are settled below. Still needing an answer: J, K and the seed list confirmations with the Registrar. Written against the Enrollment and Admissions repos as uploaded on 2026-10-25.

## 1. Goal

The applicant comes to the visit with their original documents. The Registrar ticks off each document on a checklist, then presses **Mark documents received**. The system assigns the student number (`YY-NNNNN`), turns the Applicant into a Student, marks the visit `attended`, and writes a notification. Nobody types the number.

Email sending stays a separate session, as in step 6. This step writes the notification row and leaves it `pending`.

## 2. What the research found

**PLP's own rules** (PLP admission announcement "Submission Schedules", May 2026, plpasig.edu.ph):

- "Only those with COMPLETE REQUIREMENTS will be accommodated." There is no stated way to be accepted with papers missing.
- Students submit **originals and photocopies** to the Office of the University Registrar. Nothing says the Registrar scans them.
- The Endorsement Slip signed by the Admissions Officer must be secured **before** submitting to the Registrar.
- The Student Information Form is filled in online, printed, and submitted with the other papers.
- **Form 137 is the one exception.** The Registrar gives a letter of request so the student can get the original "Copy for PLP" from their previous school, and it is submitted later, within a deadline the notice gives by academic year. So Form 137 is a late item, not a gate.

**How Admissions behaves** (`core/helpers.php`, `modules/documents/staff_action.php`):

- A hard gate. `required_docs_all_approved()` must be true before an applicant moves on to the exam. There is no override for missing documents.
- Overrides exist only for released results and Professor recommendations, and they always require a written reason (Admin only for released results).
- Admissions is where scans live. Applicants upload digital copies, an AI check flags the wrong category, and staff approve each file. Enrollment never receives those files (the intake contract carries none).

## 3. Decisions

| # | Question | Decision | Status |
|---|---|---|---|
| A | Does Enrollment keep scans of documents? | **No, not in this step.** Admissions already holds approved scans. The visit is for paper originals that PLP keeps, and no PLP source says the Registrar scans them. A second copy of IDs and birth certificates only adds privacy exposure and the riskiest part of the earlier draft (Storage bucket, policies, signed links). The checklist is a tick. Scans can be added later if the Registrar asks. | Proposal, based on research |
| B | Can the Registrar mark received with required documents missing? | **No.** Promotion is a hard gate, matching PLP ("complete requirements only") and the Admissions pattern. No override, no typed reason. The one real exception is Form 137, handled as a late item (decision L). | Proposal, based on research |
| C | Where does "what to bring" come from? | The **checklist for the applicant's admission type** is the one source. The slot field becomes optional extra notes. `assign_visit_slot` is replaced in the new migration so the notification and the card show the type's list plus the slot notes. This changes step 6 (the slot form no longer requires the field). | **Settled by you** |
| D | Checklist model | A catalog table `document_requirements` (seeded) and the existing `documents` table reshaped so one row means one document for one applicant. No rows are pre-created. Missing row = not received. A catalog change never needs a data fix. | Proposal |
| E | How promotion happens | One database function `mark_documents_received`. It uses the existing student number and promotion triggers **unchanged** (decisions #2 and #9). Never touch `generate_student_number()` or `promote_applicant_to_student()`. | Follows #2, #9 |
| F | Applicant with no visit booking | Allowed. The booking is set to `attended` only if one exists in `booked` status. | Proposal |
| G | Edits after promotion | **Required** items are locked once the applicant is a student (a correction goes through Admin). **Late** items (decision L) stay tickable. | Proposal |
| H | The "endorsed" marker carried from step 6 | The **Endorsement Slip** is a required checklist item. PLP requires it before the Registrar accepts anything, so ticking it is the visible marker. No new field. | Proposal |
| I | No show | Still not set by anything (step 6 decision F). Step 12 is the first place that needs it. | Carried |
| J | Editing the catalog | **No editor in this step.** Seeded by migration. The editor belongs with content population (step 15). Until then a change is a new migration. | Needs OK |
| K | Balik Aral | PLP runs a Balik Aral program (TOR "Copy for PLP", like transferees). Admissions sends only `new`, `transferee`, `foreign`. Confirm Balik Aral applicants arrive as `transferee`. | Needs answer |
| L | Late documents | Catalog rows can be `required = false`. They never block promotion and stay tickable after it. Seeded only for **Form 137**. No due date is stored in this step, so the Registrar follows up by the PLP deadline. | Proposal |

## 4. What exists today

- `documents` table (init migration, section 4): `applicant_id`, `doc_type` limited to four values, `storage_path NOT NULL`, `uploaded_by NOT NULL`. No code reads or writes it. Policy `documents_registrar` (Registrar) plus `admin_all`. It already has an audit trigger.
- `students` insert is handled by `trg_students_promote` (Registrar or Admin only, assigns the number, stamps who and when) and `trg_students_flip_role` (sets `users.role = 'student'`). `prevent_student_number_edit` blocks changes. `generate_student_number()` is revoked from everyone except the trigger path.
- `visit_bookings.status` already allows `attended`. `assign_visit_slot` refuses to move a booking that is not `booked`. `assign_unassigned_visits` skips applicants who are already students.
- `notifications` has everything needed. Only Admin writes directly, so a security definer function writes the row (same pattern as step 6).
- `users_registrar` lets the Registrar read applicant and student users, so names still resolve after the role flip.
- The app: `features/documents-and-numbering/` is an empty folder. `/registrar` and `/admin` are placeholder homes with a Visits link. The next step card (`features/next-step-card/queries.ts`) returns `none` for any role except applicant. `/student` is a placeholder.
- Admissions lists documents per type in `config/app.php` (`DOCS_CORE`, `DOCS_FRESHMAN`, `DOCS_TRANSFEREE`, `DOCS_FOREIGN`). Enrollment receives none of that, so it keeps its own list.

## 5. Design

### Database (one forward-only migration, `20261025050000_documents_and_numbering.sql`)

1. **`document_requirements`**: `doc_type` (text, unique key), `label`, `applies_to text[]` (any of `new`, `transferee`, `foreign`), `required boolean`, `sort_order`, `active`. Readable by any signed-in user (labels are not sensitive and the card shows them). Written by Admin only. Audit trigger and `admin_all` added in the migration, because the init migration's loops are fixed lists.
2. **Reshape `documents`**: replace the `doc_type` check with a foreign key to `document_requirements(doc_type)`. `storage_path` and `uploaded_by` become nullable and stay unused for now (decision A). Add `received_at`, `received_by`, `note varchar(200)`. One row per applicant and `doc_type` (unique). The table has no rows today because nothing writes it. Confirm that on production before applying.
3. **Guard trigger** `enforce_documents_open` on `documents`: once the applicant has a `students` row, it refuses changes to **required** items (decision G) and allows changes to late items. Admin is not exempt, to keep the rule simple. Say if you want an Admin exception.
4. **`mark_documents_received(p_applicant uuid) returns uuid`** (security definer, Registrar and Admin only, checked inside):
   - locks the applicant row, refuses if a student row already exists;
   - lists active **required** documents for the applicant's admission type that are not received. If any are missing it raises a message naming them. There is no override (decision B);
   - inserts the `students` row (existing triggers number and promote);
   - sets the applicant's `booked` visit booking to `attended`;
   - writes the `notifications` row, kind `documents_received`, `email_status = 'pending'`, with the student number in the message;
   - returns the student id. Any error rolls everything back together.
5. **Replace `assign_visit_slot`** (`CREATE OR REPLACE`, decision C) so `what_to_bring` is the applicant type's checklist plus the slot notes. Same arguments, same checks, same notification kinds. This is the only existing function touched.
6. Execute is revoked from `public` and `anon` on the new function, as in step 6.
7. Added while building: `document_checklist_text(type)` (the checklist as text, used by `assign_visit_slot` and the applicant card) and, in a second migration `20261025060000_my_open_late_items.sql`, `my_open_late_items()`, because a Student cannot read `documents` but their card must name an open late item.

No Storage bucket, no `storage.objects` policies and no `config.toml` change in this step.

### Seed for `document_requirements` (draft, the Registrar confirms)

| doc_type | Label | Applies to | Required | Source |
|---|---|---|---|---|
| `endorsement_slip` | Endorsement Slip signed by the Admissions Officer | all | yes | PLP announcement |
| `psa_birth_cert` | PSA birth certificate, original and photocopy | all | yes | PLP announcement |
| `photo_2x2` | One recent 2x2 photo, white background | all | yes | PLP announcement |
| `student_info_form` | Printed Student Information Form | all | yes | PLP announcement |
| `valid_ids` | Two valid IDs, original and photocopy, one showing current address | new, transferee | yes | PLP announcement |
| `form_138` | Form 138 (report card) | new | yes | PLP announcement |
| `tor` | TOR marked "Copy for PLP" | transferee, foreign | yes | PLP announcement (transferee), Admissions `DOCS_FOREIGN` |
| `form_137` | Original SHS Form 137 marked "Copy for Pamantasan ng Lungsod ng Pasig" (submit later) | new | **no (late)** | PLP announcement |
| `passport` | Passport | foreign | yes | Admissions `DOCS_FOREIGN` only |
| `visa_permit` | Visa or Study Permit | foreign | yes | Admissions `DOCS_FOREIGN` only |
| `acr` | Alien Certificate of Registration | foreign | yes | Admissions `DOCS_FOREIGN` only |
| `other` | Other document (note required) | all | no | Registrar's choice |

Things to confirm with the Registrar's office:

- **Foreign students.** PLP's announcement lists nothing for them. The Admissions comment says its foreign list is "kept for system completeness", so the three foreign rows are not backed by a PLP source.
- Do transferees also owe Form 137 later? The notice does not say who it applies to.
- Do foreign students bring valid IDs on top of the passport?
- Admissions also asks for a barangay certificate, a marriage certificate (if married) and a guardianship affidavit (if not living with parents). None is on PLP's announcement, so none is seeded. The `other` row covers them if needed.
- The Form 137 deadline: the announcement states it by academic year, which reads as a date from last year. The Registrar should state the real deadline for this cycle.

### Registrar page

- `app/(portal)/registrar/documents/page.tsx`, linked from the Registrar home and the Admin home, next to Visits.
- List of applicants who are not students yet, with search (name, applicant ref, email) and a program filter. Each row: name, applicant ref, program, admission type, visit date (or "No visit yet"), and required documents received out of required (for example 3 of 6). A **Received** tab shows students with their number, date, who received them, and any late items still open (read only). Fewer than 5 rows renders as a list, not a table (`ux-ui-guidelines.md`).
- Clicking a row opens the checklist, in the same pattern as `SlotDetailsModal`. Each document has a **Received** checkbox and a short note. Late items are labelled "Can be submitted later". Primary action **Mark documents received** is bottom right and stays disabled, naming what is missing, until every required item is ticked. It opens a confirmation that says plainly: this gives the student number and turns the applicant into a student, and it cannot be undone.
- After success the modal shows the new student number and closes on **Done**.
- Files follow the feature folder rule: `features/documents-and-numbering/` holds `schema.ts` (input checks: note length, uuid), `queries.ts`, `actions.ts` (check the caller, then run under the caller's session, per decision #10) and the list and checklist components. The `failure()` pattern for database messages is copied from `visit-scheduling/actions.ts`.

### "Your next step" card

- `getNextStep` gets a student case: `kind: 'student_waiting'` with the student number. Text: "Your documents were received. Your student number is YY-NNNNN. Your college will prepare your schedule and you will see it here." If a late item is still open, the card adds a line naming it. No office or time is invented.
- The applicant card with a visit now reads the checklist for their type (decision C) instead of the slot text alone.
- Other roles keep "Nothing to do yet" until step 14.

## 6. Build order

Each step ends in something that can be checked. Read `docs/ux-ui-guidelines.md` and `scripts/design-gate.mjs` before step 4, so the pages pass the design gate.

1. **Your answers** on J, K and the seed list, and approval of the schema change.
2. **Migration** `20261025050000_documents_and_numbering.sql` (section 5).
3. **Database checks** added to `supabase/gates_check.sql` (section 7).
4. **Feature code**: `schema.ts`, `queries.ts`, `actions.ts`.
5. **Registrar page**, the checklist and the links from the Registrar and Admin homes.
6. **Next step card** student case and the updated applicant card.
7. **Docs**: build step 7 ticked in `build-order.md`. Add a decision-log entry for the hard gate with late items (B and L) and one for the catalog replacing the slot text (C), since both are hard to reverse and touch several parts. Update the step 6 note in `step-6-visit-scheduling-plan.md` for C.

## 7. Acceptance checks

- A required document that is not received blocks promotion with a message naming it. There is no way around it, for the Registrar or Admin.
- A late item (Form 137) that is not received does not block promotion.
- Promotion creates exactly one `students` row, a `YY-NNNNN` number, flips the role to `student`, sets a `booked` booking to `attended`, and writes one `documents_received` notification with `email_status = 'pending'`. Any failure leaves none of these behind.
- An applicant with no booking can be promoted. A booking already `attended` or `no_show` is left as it is.
- Two Registrars promoting the same applicant at once: one succeeds, the other gets "already a student". No second number is consumed. A refused promotion does not burn a number.
- An Applicant, Student, Finance, Dean or College Secretary calling the function directly is refused. Registrar and Admin succeed. Only Registrar and Admin read or write `documents`.
- After promotion a required item cannot be changed and a late item still can. The student number cannot be edited (existing check, rerun).
- The checklist for each admission type shows exactly its seeded rows. A row that does not apply to the type is not counted.
- The Student sees their number on the card, plus any open late item. The Applicant card shows their type's list.
- Every checklist tick and promotion writes an audit row with the actor.
- The pages pass lint, type check, and the design gate in CI, and the migration passes `supabase db reset` and `db lint` in CI.

## 8. Risks and open items

- The student number is permanent and printed later on the slip and COR. A wrong promotion cannot be undone. That is why the confirmation text is explicit and required items lock afterwards. A mistaken promotion needs an Admin fix, and the number stays used.
- The hard gate means a student missing one paper cannot be enrolled on the day. That matches PLP's stated rule, but if the Registrar's office quietly allows exceptions in practice, tell me and we add a controlled state later. This plan does not.
- The Form 137 deadline is not stored, so nothing flags it as overdue until the dashboards in step 14.
- The seed list comes from a public announcement and the Admissions config. The Registrar owns it each cycle, and until step 15 a change is a new migration.
- Decision C changes a step 6 behavior (the slot "what to bring" field).
- Pending emails pile up until the sender session (same as step 6).

## 9. Not in this step

- Scans or any file storage for documents.
- Editing the document catalog (step 15).
- The Registrar's letter of request for Form 137.
- Sections, professors and rooms (step 8), the assessment slip (step 9), payment (step 10), the COR (step 11).
- No show handling, reschedule paths (step 12).
- Sending the emails (env vars session).
- Role dashboards beyond the card (step 14).
- Any change to the Admissions repo.
