# decision-log.md

---
## AI RULES — READ FULLY BEFORE ANY ACTION
---

1. Read all existing entries before suggesting anything already decided.
2. Never re-debate a logged decision. If it needs revisiting → flag it,
   don't silently override it.
3. At every major milestone → check whether a decision qualifies
   under rule 4. If it does, add an entry.
4. Log only truly major decisions. Apply this filter — a decision must
   pass ALL three, otherwise do not log it:
   - Hard to reverse?
   - Affects multiple parts of the system?
   - Confusing without an explanation?
   Never log: naming, styling, small library choices, bug fixes,
   refactors, or anything easily changed later.
   When unsure → do not log.
5. Before presenting options at a milestone → search current community
   consensus on each direction. Present findings, then wait for human
   decision before logging.
6. If two directions were discussed with the human → both get logged,
   with the reason the chosen path was taken.
7. Keep every entry tight. Maximum 2 sentences per field. No
   background stories, no repeating context from other files.

---
## DECISION ENTRIES
---

### Entry Format — copy this block for each new decision

**#:**
**Date:**
**Milestone:** (e.g. "Project start", "30% — authentication approach")

**Context:**
What situation or problem forced this decision?

**Options Considered:**
- Option A:
- Option B:

**Community Consensus:**
What do experienced developers say about each option today?
(AI: search this before the milestone conversation — do not fill from memory alone)

**Decision:**
What was chosen and why?

**Consequences:**
What does this decision affect going forward?
What becomes harder or easier because of this choice?

---

**#:** 1
**Date:** Pre-build (carried over from enrollment-plan.md)
**Milestone:** Project start

**Context:** Enrollment needs applicant data from the separate PLP Admissions system, but the two systems must not share a database or login.

**Options Considered:**
- Option A: Shared database between Admissions and Enrollment.
- Option B: Two separate databases, linked only by one secure HTTPS call (Admissions → Enrollment) using a shared secret.

**Decision:** Option B. One secure web call sends applicant reference, name, email, program, admission date/type, and source; the shared secret lives in hosting settings on both sides, never in code.

**Consequences:** Enrollment must validate and store every inbound request (success or failure, who/when) and expose an Admin view to see, resend, and toggle the connection. Enrollment must reject any program code it doesn't recognize with a clear message, and must support all 13 Admissions program codes including BSENT, which the prior system lacked.

---

**#:** 2
**Date:** Pre-build (carried over from enrollment-plan.md)
**Milestone:** Project start

**Context:** The student number is a permanent identifier that downstream documents (assessment slip, COR) and records depend on.

**Decision:** The system assigns the student number automatically, only when the Registrar marks the original documents received — nobody types it, one number per student, never reused, never editable afterward. This is also the exact moment an Applicant becomes a Student.

**Consequences:** Student-number generation logic is a "never touch without approval" area per architecture-notes.md once built. Every downstream document and permission check keys off this transition.

---

**#:** 3
**Date:** Pre-build (carried over from enrollment-plan.md)
**Milestone:** Project start

**Context:** PLP's 2024 Registrar Citizen's Charter has the Dean issuing the assessment slip and no Finance step for new students; some courses (e.g. Psychology) do require payment.

**Decision:** Diverge from the charter: the Registrar (not the Dean) issues the assessment slip and COR. Payment is a per-course toggle, changeable by Admin and Finance (view-only for Registrar and Dean), with Finance's step sitting between the assessment slip and the COR, and skipped entirely when the toggle is off.

**Consequences:** Every payment-toggle change must be audit-logged. The Finance step becomes conditional logic in the enrollment flow rather than a fixed step, which the UI and backend must both branch on.

---

**#:** 4
**Date:** Pre-build (carried over from enrollment-plan.md)
**Milestone:** Project start

**Context:** PLP's college charters conflict on who runs schedule/professor-loading steps — the 2024 Registrar charter names the Dean, newer college charters show the College Secretary doing the hands-on work.

**Decision:** The College Secretary (the Dean's assistant) does the day-to-day work — advising, preparing sections, assigning professors and rooms — but the Dean must sign off on professor loading before it reaches the Registrar. The Dean can also do everything the Secretary does.

**Consequences:** The schedule-approval flow has three sequential gates (Secretary prepares → Dean signs off → Registrar approves) that cannot be collapsed or reordered without revisiting this decision. RBAC must allow the Dean to act in the Secretary's role.

---

**#:** 5
**Date:** Pre-build (carried over from enrollment-plan.md)
**Milestone:** Project start

**Context:** A visit date can move either because of an office-wide disruption or a single student's emergency, and the plan requires students never pick their own slot.

**Decision:** Two separate reschedule paths: (1) mass reschedule, triggered only by Registrar or Admin, auto-moves every affected student with no loss of place/no-show status; (2) student-initiated request, reviewed and approved/declined only by the Registrar. Both are audit-logged (who, what, when, why) and only change the visit date — never progress, student number, or documents.

**Consequences:** Two distinct reschedule code paths and permission sets are required, not one generic "reschedule" feature. Student-facing UI must only ever expose a "request," never a "pick" or "move."

---

**#:** 6
**Date:** 2026-10-24
**Milestone:** Project start — stack selection

**Context:** Needed a concrete tech stack before any folder structure or code could be proposed; the human specified the tooling.

**Decision:** Next.js (App Router) + Mantine UI, PostgreSQL via Supabase, hosted on Vercel, Manrope + Plus Jakarta Sans fonts. Enrollment is a fully separate system from PLP Admissions — its own Vercel project, own Supabase project, own database and logins — connected only via the one outbound HTTPS webhook described in enrollment-plan.md.

**Consequences:** Admissions (PHP/MySQL-via-Postgres on Vercel) and Enrollment (Next.js/React on Vercel) are two independently deployed codebases with no shared runtime or ORM. Inspecting the Admissions repo confirmed it has no applicant reference field, no outbound webhook code, and no shared-secret config yet — the `confirm_enrollment` action in `modules/results/enrollment_intent.php` only flips a local flag. Enrollment's intake endpoint is being built to the contract enrollment-plan.md specifies, but Admissions-side changes (generating an applicant ref, calling out, the shared secret, the retry button) are a separate, currently unscoped piece of work — see open-questions.md #5.

---

**#:** 7
**Date:** 2026-10-24
**Milestone:** Project start — design tokens

**Context:** ux-ui-guidelines.md requires an established, not invented, color palette. Presented Tailwind Slate/Blue and GitHub Primer as sourced options.

**Decision:** GitHub Primer (neutral/gray scale + Primer blue accent), chosen for fitting a dense, data-heavy admin/registrar tool. Values sourced from Primer's published scale (gray 0–1000, blue 0–9).

**Consequences:** All color tokens in `styles/tokens.ts` derive from this scale. Any future accent needs (success/warning/error) should pull from Primer's green/yellow/red scales to stay consistent, not be invented ad hoc.

---

**#:** 8
**Date:** 2026-10-25
**Milestone:** Project start — CI/CD approach

**Context:** The human wants every push to validate the code and update the Supabase database automatically, with production as the only environment.

**Options Considered:**
- Option A: Production only, auto-deploy and auto-migrate on merge to main (GitHub Actions).
- Option B: Staging + production, with migrations tested on staging first.

**Community Consensus:** Supabase's docs recommend deploying migrations through a GitHub Actions pipeline rather than from a local machine. Their example uses separate staging and production projects, so production-only is a lighter setup than the documented pattern.

**Decision:** Option A, chosen by the human. Checks: lint, type check, build, SonarQube, design gate, light security.

**Consequences:** A faulty migration reaches live data with no staging buffer, which matters for student numbering, payments and the audit log. Guardrails copy Lakbay Pasig: forward-only migrations, a `db reset` test and `db lint` in CI. The production Vercel deploy runs from the workflow after the migration, so Vercel's Git auto-deploy is off for main.

---

**#:** 9
**Date:** 2026-10-25
**Milestone:** Documents & numbering: student number format

**Context:** The student number is permanent and printed on the slip and COR, and the first schema used a plain 8 digit sequence as a placeholder.

**Decision:** Format `YY-NNNNN` (year of assignment in Manila time, a dash, a 5 digit counter that restarts each year), chosen by the human. Counters live in `student_number_counters`, handed out under a row lock.

**Consequences:** Changing the format later would not renumber existing students. Past 99999 numbers in one year the system refuses to assign more, so the format must change before that.

---

**#:** 10
**Date:** 2026-10-25
**Milestone:** Auth and roles: how server code identifies the user to the database

**Context:** `lib/db.ts` uses a superuser connection that bypasses row level security, so the database rules for Registrar, Finance, Dean and the others would not apply to real people.

**Options Considered:**
- Option A: Server code uses the signed-in person's Supabase session (`@supabase/ssr`), so the database sees `auth.uid()`.
- Option B: Keep `pg` and set `app.actor_id` per transaction.

**Community Consensus:** Supabase's current SSR guide for Next.js uses cookie-based sessions with `@supabase/ssr`, middleware that refreshes the token, and `getClaims()` to check the session. Option B is a supported fallback in this schema but means every query path must set the actor correctly and row level security is bypassed if one forgets.

**Decision:** Option A, approved by the human in the step 4 plan. The role is read from the `users` table on each request, not from the token, so an Applicant who becomes a Student is treated as one at once.

**Consequences:** User-initiated reads and writes go through `lib/supabase/server.ts`, so row level security and the audit log see the real person. `lib/db.ts` is kept only for system jobs with no signed-in person, such as the Admissions intake webhook.

---

**#:** 11
**Date:** 2026-10-25
**Milestone:** Admissions intake: how the one call from Admissions works

**Context:** Decision #1 fixed one secure call with a shared secret, but not its exact form, who it runs as, or how a retry works.

**Options Considered:**
- Option A: One idempotent endpoint, `POST /api/admissions/intake`, with `Authorization: Bearer <ADMISSIONS_INTAKE_SECRET>`. Retries call the same endpoint.
- Option B: A separate resend endpoint for Admissions' retry button.

**Community Consensus:** Webhook guidance from Stripe and similar providers is to verify a shared secret and make receivers idempotent, because senders retry. A second endpoint only adds a second path to secure.

**Decision:** Option A. The receiver runs as the system with the service role key, not a person. The applicant ref makes a repeat a refresh while the person is an Applicant and a no-op once they are a Student.

**Consequences:** The JSON keys in `features/admissions-intake/schema.ts` are the contract the Admissions sender must follow. Every authenticated request is logged, but a request that fails validation is logged with placeholder values because the log columns are required; the real body is kept in `raw_payload`.

---

**#:** 12
**Date:** 2026-10-25
**Milestone:** Admissions sender: how accounts and roles connect

**Context:** Admissions and Enrollment each have their own users and roles. Admissions has student, professor, proctor, SSO, Dean and Admin. Enrollment has applicant, student, Registrar, Finance, Dean, College Secretary, Professor and Admin.

**Options Considered:**
- Option A: Link the applicant account by `applicant_ref` and email. Staff accounts stay separate, matched in a documented role table.
- Option B: Also create or update Enrollment staff accounts from Admissions.
- Option C: Shared sign-in across both systems.

**Community Consensus:** Not searched. This follows decision #1 (separate databases and logins), and option A is the only one that needs no second signed endpoint.

**Decision:** Option A. Only an Admin creates staff accounts in Enrollment. If staff ever need one sign-in, use a shared identity provider (for example Google on the school domain) rather than a shared database.

**Consequences:** Roles are never synced. The applicant link is the `applicant_ref` plus the email, and a name or email change reaches Enrollment only by a resend. Options B and C need a new decision entry.

---

**#:** 13
**Date:** 2026-10-25
**Milestone:** Admissions sender: foreign applicants

**Context:** Admissions has three applicant types: freshman, transferee and foreign. Enrollment accepted only `new` and `transferee`.

**Options Considered:**
- Option A: Send foreign applicants as `new`.
- Option B: Add `foreign` to the contract.

**Community Consensus:** Not searched.

**Decision:** Option B. Foreign students need different documents, and folding them into `new` loses that with no way to recover it. Migration `20261025030000_admission_type_foreign.sql` widens the check on `applicants` and `admissions_intake_log`.

**Consequences:** `features/admissions-intake/schema.ts` accepts `foreign`. The documents step (build step 7) must branch on it.

---

**#:** 14
**Date:** 2026-10-25
**Milestone:** Admissions sender: one source for the visit date

**Context:** Admissions has its own single "Enrollment Schedule" (date, time, venue) that gates releasing an acceptance. Enrollment will set visit slots per program (build step 6).

**Decision:** Leave the Admissions schedule alone until Enrollment build step 6 ships, then retire it and replace its release gate, so a student sees one date from one system.

**Consequences:** Build step 6 includes that cleanup. Until then a student can see the Admissions date and, later, an Enrollment date.

---

**#:** 15
**Date:** 2026-10-25
**Milestone:** Build step 6, visit scheduling

**Context:** PLP's real process lets applicants reserve a slot through an Enrollment Link from Admissions, with submission dates per program, and requires an Endorsement Slip signed by the Admissions Officer before the Registrar takes documents (plpasig.edu.ph notice of 2026-05-15). Admissions has one global schedule and no slip. Decision #14 already said to retire that schedule once Enrollment sets visit slots.

**Options Considered:**
- Option A: Applicants reserve a slot themselves, as PLP does today.
- Option B: The Registrar assigns slots; the applicant only sees the result.
- Option C: Keep the Admissions schedule and the release gate.

**Community Consensus:** Not searched. The choice follows the request that applicants never pick a slot (build step 6 plan, decision A).

**Decision:** Option B. The Registrar presses "Assign all unassigned" per program, or assigns and moves one applicant. The booking and its notification are written by database functions in one transaction. Admissions changes after go-live: the schedule block becomes an Endorsement Slip with no date, and the `enrollment_schedule_posted()` gate is dropped, because it only protected the student's view and no data depends on it. Attendance (`attended`, `no_show`) is not set in step 6; step 7 sets `attended` when documents are received.

**Consequences:** Applicants no longer reserve a slot, so tell the Registrar's office before go-live. A slot with bookings keeps its program, date, time and office; moving people is the mass reschedule in step 12. "What to bring" is a required slot field, pre-filled with PLP's published list. Whether the Registrar needs a visible "endorsed" marker is open for step 7.

---

---

**#:** 16
**Date:** 2026-10-25
**Milestone:** Build step 7, documents and student numbering

**Context:** PLP accepts "complete requirements only" and keeps the paper originals, with one exception: the original Form 137 is submitted later. Admissions already holds approved scans, and Admissions blocks the exam until every required document is approved, with no override.

**Options Considered:**
- Option A: Promotion is blocked until every required document is ticked, and late items (Form 137) never block it.
- Option B: The Registrar may promote with documents missing, with a typed reason.
- Option C: Keep scans of documents in Enrollment.

**Community Consensus:** Not searched. Option A follows PLP's published rule and the Admissions pattern; no PLP source says the Registrar scans originals.

**Decision:** Option A. `mark_documents_received` refuses and names what is missing, for Registrar and Admin alike. A late item is a catalog row with `required = false`, never blocks promotion and stays tickable after it. No scans are stored (Option C dropped).

**Consequences:** A student missing one paper cannot be enrolled that day, and a wrong promotion cannot be undone because the number stays used. If the Registrar's office quietly allows exceptions, that needs a new entry and a controlled state. The Endorsement Slip is a required checklist item, which settles the "endorsed" marker left open in #15.

---

**#:** 17
**Date:** 2026-10-25
**Milestone:** Build step 7, where "what to bring" comes from

**Context:** Step 6 made "what to bring" a required text field on each visit slot, so the applicant's list and the Registrar's checklist could drift apart.

**Options Considered:**
- Option A: The catalog `document_requirements`, per admission type, is the one source; the slot field becomes optional extra notes.
- Option B: Keep the slot text and build a separate checklist.

**Community Consensus:** Not searched. Option B keeps two lists that must be edited together.

**Decision:** Option A, chosen by the human. `assign_visit_slot` writes the type's checklist followed by the slot notes, and the applicant card reads the same list. The catalog is seeded by migration and has no editor until step 15.

**Consequences:** This changes the step 6 slot form (the field is optional and no longer pre-filled), so slots saved before step 7 may repeat the old list after the checklist and should be cleaned by hand. A change to the document list is a new migration until step 15.

---

**#:** 18
**Date:** 2026-10-25
**Milestone:** Build step 8, rejecting a schedule

**Context:** The schedule chain (decision #4) only moved forward. Nothing said what a Dean or Registrar does when the loading is wrong.

**Options Considered:**
- Option A: Reject sends the schedule back to draft with a required reason.
- Option B: Reject goes back one gate only.
- Option C: No rejection; corrections go through Admin.

**Community Consensus:** Not searched. This is a workflow choice for PLP, not a technical one.

**Decision:** Option A, chosen by the human. `reject_schedule` sets the status to draft and stores the reason; the Dean may reject from "waiting for Dean", the Registrar from "waiting for Registrar", never from approved. The gates still cannot be skipped or reordered.

**Consequences:** A Registrar rejection discards the Dean's sign-off, so the Dean signs the corrected loading again. A schedule cannot be submitted with a subject missing a professor, room or time.

---

**#:** 19
**Date:** 2026-10-25
**Milestone:** Build step 8, placing students in sections

**Context:** Students need a section before the schedule means anything to them. Applicants do not record a year level.

**Options Considered:**
- Option A: Automatic placement, with the Secretary or Dean able to move a student at any time.
- Option B: Secretary and Dean place every student by hand.
- Option C: Automatic, only after the Registrar approves the schedule.

**Community Consensus:** Not searched. Option A follows the "automate what is safe" rule in the plan.

**Decision:** Option A, chosen by the human. Placement runs when a student is promoted, when a section is created and when a capacity goes up: first section of the student's program at year level 1 with a free seat, by section name. A manual move may go over capacity and is refused once the assessment slip exists.

**Consequences:** `sections.capacity` is required. Every new student lands in year level 1, so a transferee who belongs higher up must be moved by hand. A student with no seat waits and is placed when a seat appears.

---

**#:** 20
**Date:** 2026-10-25
**Milestone:** Build step 8 follow-up, laboratory meetings

**Context:** The sample PLP Certificate of Registration lists a subject's lecture and laboratory as separate rows with their own room, day and time, and units on the lecture row only. Step 8 allowed one row per subject in a section.

**Options Considered:**
- Option A: A `meeting` column (lecture or laboratory) on each section row, filled automatically from a `has_laboratory` flag on the subject.
- Option B: Treat a laboratory as its own subject in the catalog, with its own code and no units.
- Option C: The Secretary adds a laboratory row by hand per section.

**Community Consensus:** Not searched. This follows the layout of PLP's own COR.

**Decision:** Option A. The human chose to allow lecture and laboratory rows per subject; filling them from a catalog flag is the AI's design and is open to change. New sections, and subjects added or flagged later, get a laboratory row automatically; the row carries no units, so units are counted once on the slip and the COR.

**Consequences:** The catalog (step 15) must set `has_laboratory` correctly; until then Admin sets it directly. Rows already created for a subject are not removed if the flag is turned off.

---

**#:** 21
**Date:** 2026-10-25
**Milestone:** Build step 11, what the COR shows

**Context:** PLP's COR carries a school year and semester and an itemized fee assessment, but nothing in the system stores a term or a fee schedule.

**Options Considered:**
- Option A: A one-row `enrollment_term` table set by Admin, copied onto each COR when it is issued; the COR shows Finance's recorded amounts instead of fee lines.
- Option B: Add a fee schedule (tuition rate, miscellaneous, laboratory) and itemize the COR.

**Community Consensus:** Not searched. This follows the data the system actually holds.

**Decision:** Option A, the AI's design for the human to veto. Issuing a COR is refused until Admin sets the term, which is set by SQL until step 15. Fields with no data (enrollment number, adjustment number, curriculum, scholarship, old account, midterm and final due) are left off.

**Consequences:** An old COR never changes when the term changes. Itemized fees need a fee schedule and a new decision.

---

**#:** 22
**Date:** 2026-10-25
**Milestone:** Build step 10, how a payment clears

**Context:** Finance records what a student paid, and the COR waits on it. The plan did not say whether part of a fee counts.

**Options Considered:**
- Option A: A payment clears only when the amount paid covers the amount due.
- Option B: Record partial payments and clear when the total is reached.

**Community Consensus:** Not searched. Option A matches the existing `payments` table, which allows one row per student and a cleared check of paid at least due.

**Decision:** Option A, the AI's design for the human to veto. The per-program toggle affects only slips issued afterwards, because each slip keeps its own snapshot.

**Consequences:** An installment plan needs a payments ledger and a new decision. Switching a program's toggle does not reopen or skip anything for students who already have a slip.

---

**#:** 23
**Date:** 2026-10-25
**Milestone:** Build step 12, how reschedules choose and answer

**Context:** The plan lets staff move a date by a mass reschedule "to the next available slot, or to a new date that staff set", and lets the Registrar answer a request by approving, declining, or "offering the next available date". It does not say what happens to a person who does not fit, whether staff may pick the target, or how a declined person sees the answer.

**Options Considered:**
- Option A: A mass reschedule always moves to the next open slot of the person's program, never onto the date being emptied (and never onto the office being emptied when one office is chosen). Staff do not pick a target. Someone who does not fit stays where they are and is counted, so the Registrar adds slots and runs it again. Approving a request takes an optional slot, or the next open slot on another date. Declining needs a note, shown on the person's card and sent as a notification.
- Option B: Let staff pick a target slot, or park people with no booking until a slot exists.

**Community Consensus:** Not searched. Option A follows what the database already holds: `mass_reschedules.target_slot_id` stays empty, and the visit is never left without a booking.

**Decision:** Option A, the AI's design for the human to veto. Only visits still marked booked move; attended and no show stay as they are. A person may have one waiting request per visit and may ask again after a decline. Declining does not offer a date, because the Registrar can approve with a chosen slot instead.

**Consequences:** A mass reschedule on a busy day can leave people on the date being emptied until slots are added. A no show visit has no way to ask for a reschedule yet, because nothing in the system marks a no show.

---

**#:** 24
**Date:** 2026-10-25
**Milestone:** Build step 13, what the audit log page shows

**Context:** The plan says the audit log records who, what, when (and why when given) and that Admin can see it. It does not say how Admin browses a table that only grows, whether the page can change or hide anything, or what to show for a system action.

**Options Considered:**
- Option A: A read only page, newest first, 50 per page, with filters for table and action kept in the URL. Each entry has a Details window showing the fields that changed, before and after. An entry with no signed-in person shows as "System". No new migration.
- Option B: Add search by person or record, a date range and an export, with a database function to serve them.

**Community Consensus:** Not searched. Option A needs nothing the database does not already hold: `audit_log` is append only, and only Admin can read it.

**Decision:** Option A, the AI's design for the human to veto. The page has no edit or delete control of any kind. Names are looked up from `users` because `audit_log.actor_id` has no foreign key, so a removed account shows as "Unknown account" while its entries stay.

**Consequences:** Finding one person's or one record's history means scrolling or filtering by table for now. The table filter is a fixed list in `features/audit-log/schema.ts`, so a newly audited table needs one line added there.

---

**#:** 25
**Date:** 2026-10-25
**Milestone:** Build step 14, what each home screen shows

**Context:** The plan says every page ends with a "Your next step" card, but the card only has content for Applicants and Students. Staff saw "Nothing to do yet" above pages with work waiting. The guidelines ask for what needs action first, no stat cards without an action, and no repeated calls to action.

**Options Considered:**
- Option A: Applicant and Student get a stepper of their position and keep the card for details and actions. Staff get a list of their pages with a count of what waits on each, pages with work first, and the card is not shown to them. Registrar and Admin add an enrollment funnel. A Professor sees their load and class lists.
- Option B: Keep the card for staff and fill it with the same counts, or show a row of stat cards on every home.

**Community Consensus:** Not searched (no web search in the session). The guidelines' own dashboard and linear flow rules point to Option A.

**Decision:** Option A, the AI's design for the human to veto. This changes the plan's "every page ends with a next step card" for staff and Professors only. The Payment step appears in the stepper only once the slip says it is required, because a student cannot read the program toggle. A Professor sees only subjects in approved schedules, so a draft loading is never shown. The Documents count is applicants whose visit date is today or earlier and who are not students yet.

**Consequences:** A Finance home has one row until more pages exist. The counts read the same tables the pages read, so a count and its page can differ only by timing. No Professor class list exists for a subject until students are placed in its section.

---

**#:** 26
**Date:** 2026-10-25
**Milestone:** Build step 15, how content gets into the system

**Context:** The build order lists colleges, programs, subjects, rooms and staff accounts as one content task. Colleges, the 13 programs and the staff account form already exist. Subjects and rooms had no editor, and the school year and semester needed SQL before any COR could be issued.

**Options Considered:**
- Option A: Admin editor pages: subjects (one program at a time), rooms and the current term, all under one Content page. Colleges and programs stay as seeded. The real data is entered by Admin through the pages.
- Option B: A seed migration or a CSV import with the real PLP curriculum, rooms and term.
- Option C: Also add editors for colleges and programs.

**Community Consensus:** Not searched. Option A needs no migration, because Admin already has write access to these tables and a database trigger fills sections from the subject catalog.

**Decision:** Option A, the AI's design for the human to veto. Adding a subject needs its program and year level, and editing keeps both, because sections were filled from them. A subject or room that a section uses cannot be deleted (the database refuses it). Changing the term never alters an issued COR, because each COR keeps its own term. There is no program editor, because a program code must keep matching the course code in PLP Admissions, and a new course needs a change on both sides.

**Consequences:** No real curriculum exists until someone enters it. A CSV import would be quicker for hundreds of subjects and can be added later as its own step. An issued subject cannot move to another program or year level; it must be deleted (when unused) and added again.
