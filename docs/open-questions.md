# open-questions.md

---
## AI RULES — READ FULLY BEFORE ANY ACTION
---

1. Read this file at the start of every session and at every
   major milestone.
2. Section 1 questions are hard blockers. Do not write any code
   or make any structural decision until all Section 1 questions
   are answered by the human.
3. Section 2 questions are active blockers. Do not pass the
   milestone they are tagged to without resolving them first.
4. When uncertain mid-build → do not guess. First run the CHECK
   BEFORE ASKING below. Only if the answer is truly not found, add a
   question to Section 2 with its milestone tag, flag it to the human,
   and wait for an answer before continuing.
5. When a question is answered → move it to the Resolved log
   at the bottom. Never delete questions — resolved ones become
   part of the project's decision history.
6. Never answer your own questions with assumptions. If a question
   is here, it means a human decision is required.
7. Keep it tight. One question per row, one or two sentences. No
   background, no explaining what other files already say.

---
## SECTION 1 — BEFORE STARTING
---
These must all be answered before any code is written.
If any are blank → stop and ask.

| # | Question | Answer |
|---|----------|--------|
| 1 | What is the tech stack (frontend, backend, database, auth, hosting)? architecture-notes.md needs this before any folder structure can be proposed. | Answered 2026-10-24: Next.js (App Router) + Mantine UI, PostgreSQL via Supabase, hosted on Vercel. Fonts: Manrope and Plus Jakarta Sans. Enrollment is a fully separate system — its own Vercel project, own Supabase project/database, own logins — connected to PLP Admissions only via the one outbound HTTPS webhook described in enrollment-plan.md. |
| 2 | What is the project scale (Small / Medium / Large) per architecture-notes.md's definitions? This system has 8 roles, 2 generated documents, an inbound integration, and an audit log, which suggests Medium or Large, but the human must choose. | Answered 2026-10-24: Medium — feature-based grouping, shared utilities in one place. |
| 3 | How does the Registrar/Admin actually pick "the next available slot" or set a new date during a mass reschedule — is there a defined visit-scheduling/capacity model (rooms, times, per-program capacity) to build against, or does that need to be designed as part of this project? | Answered 2026-10-25: Simple model. A slot is a date + time window + per-program capacity. "Next available" = the earliest slot (same program) with open capacity. Designed as part of this project. |
| 4 | Does this project need CI/CD (ci-cd.md), and if so, what platform/environments? | Answered 2026-10-25: Yes, set up now. Platform, checks, environments and deploy trigger still to be specified in ci-cd.md. |

---
## SECTION 2 — ACTIVE DURING BUILD
---
Questions that surfaced mid-project.
Each question is tagged to the milestone where it must be resolved.

| # | Question | Milestone | Answered? |
|---|----------|-----------|-----------|
| 1 | What exactly triggers the "next available slot" for a mass-rescheduled student — same visit type/program, first open slot chronologically — and who defines what counts as "available" (room + time capacity)? | Reschedules (mass) | [x] See Resolved #1 |
| 2 | What format/fields does the COR need, beyond student number, section, professors, and payment status — is there an existing PLP COR template to match? | Assessment slip & COR generation | [x] See Resolved #15 |
| 3 | Should Admin's optional future "tell Admissions the student is enrolled" callback be built now or deferred, since enrollment-plan.md marks it "Later, optional"? | Connection to PLP Admissions | [x] See Resolved #11 |
| 4 | What does "retry" look like on the Admissions side's "Send to Enrollment" button — does Enrollment need a dedicated endpoint for manual resend, separate from the original webhook? | Connection to PLP Admissions | [x] See Resolved #10 |
| 5 | Confirmed from inspecting the PLP Admissions codebase: it has no applicant reference number field (e.g. ADM-2026-000042), no outbound webhook/HTTP client code, and no shared-secret config anywhere yet. `enrollment_intent.php`'s `confirm_enrollment` action only flips a local `enrollment_intent` flag — it does not call out to anything. Does the Admissions side also need to be built/modified to send the webhook (applicant ref generation, outbound call, retry button, shared secret in its env), or is that being handled separately from this conversation? | Connection to PLP Admissions | [x] See Resolved #12 |
| 6 | What should the "design gate" check on each change: fail the build when components hardcode colors, spacing, radius or fonts instead of using `styles/tokens.ts`, per ux-ui-guidelines.md? Or something else? | CI/CD setup | [x] See Resolved #2 |
| 7 | SonarQube: use SonarCloud (hosted; free tier only for public repos) or a self-hosted SonarQube server? Is the GitHub repo public or private? | CI/CD setup | [x] See Resolved #3 |
| 8 | Supabase CLI expects timestamped files in `supabase/migrations/`; the project has `db/migrations/0001_init.sql` and a `migrate` script pointing at a `db/migrate.mjs` that does not exist. Move to the Supabase CLI layout, or keep `db/migrations/` and write a custom runner? (Schema files need human approval.) | CI/CD setup | [x] See Resolved #4 |
| 9 | With production-only and auto-migrate on merge to main, which guardrails do you want: PR required with checks passing before merge, forward-only migrations, and a Supabase backup before each production migration? | CI/CD setup | [x] See Resolved #5 |
| 13 | `lib/db.ts` connects with a superuser connection string, which bypasses row level security. Should server code use the signed-in user's Supabase session, or keep `pg` and set `app.actor_id` per transaction? | Auth and roles | [x] See Resolved #9 |
| 14 | If the Dean or Registrar rejects a schedule, what happens? The schema only moves forward (draft, pending_dean, dean_signed, approved). | Section scheduling | [x] See Resolved #13 |
| 15 | Which Admin or staff role places a student into a section: Secretary and Dean only, or automatically? | Section scheduling | [x] See Resolved #14 |

---
## CHECK BEFORE ASKING
---

Before adding any question, confirm the answer is not already known.
Read thoroughly, do not skim:

1. Re-read project-brief.md, architecture-notes.md, constraints.md,
   and decision-log.md in full.
2. Read every question in this file, including Resolved. If the same
   question, or one with the same answer, exists → do not add it.
3. Check the existing code and files for the answer.
4. If the answer is found anywhere above → use it. Do not ask. Ask
   only if it is missing AND needs a human decision.

---
## HOW TO ADD A QUESTION (AI instructions)
---

When you hit uncertainty mid-build:
1. Stop what you are doing and run CHECK BEFORE ASKING
2. Write the question clearly and specifically —
   not "what should I do here?" but "should the user
   profile data be fetched on login or on page load,
   given that X and Y are both affected by this choice?"
3. Tag it to the nearest upcoming milestone
4. Tell the human: "I've added a question to open-questions.md
   before I can continue. See question #[N]."
5. Wait for the answer before proceeding

---
## RESOLVED QUESTIONS
---
Answered questions live here permanently as part of project history.

| # | Question | Answer | Resolved At |
|---|----------|--------|-------------|
| 1 | What counts as "next available slot" for a mass-rescheduled student, and who defines "available"? | Same program, earliest slot with open capacity. Slots (date + time window + per-program capacity) are set up by staff, per the plan. Answered together with Section 1 #3. | 2026-10-25, project start |
| 2 | What should the design gate check? | Fail the build when components hardcode colors, spacing, radius or fonts instead of using `styles/tokens.ts`. | 2026-10-25, CI/CD setup |
| 3 | Which SonarQube setup? | SonarQube Cloud (SonarCloud) free plan: private repos up to 50k lines of code, up to 5 users, PR and main branch analysis. | 2026-10-25, CI/CD setup |
| 4 | Where do migrations live? | Supabase CLI layout: `supabase/migrations/`, timestamped files (AI recommendation, accepted by human). `0001_init.sql` moved to `20261025000000_init.sql`; `migrate` script now `supabase db push`. | 2026-10-25, CI/CD setup |
| 5 | Which production guardrails for auto-migrate on merge to main? | Copy what Lakbay Pasig does: forward-only migrations (never edit a migration merged to main, add a new one), every migration tested with `supabase db reset` in CI, `supabase db lint`, and SQL check files. No PR requirement and no backup step (not in Lakbay). | 2026-10-25, CI/CD setup |
| 6 | What is the student number format? | `YY-NNNNN`: two digit year, a dash, a 5 digit counter that restarts each year (for example 24-00669). The counter is automatic. | 2026-10-25, Documents & numbering |
| 7 | What are the 13 Admissions program codes, names and colleges? | Taken from the PLP Admissions code (`PLP_COURSES`, `COURSE_DEPARTMENT_MAP`) and seeded: BSA, BSBA, BSENT (College of Business and Accountancy), BSHM (Hospitality Management), BEED, BSED-ENG, BSED-FIL, BSED-MATH (Education), AB Psych (Arts and Sciences), BSCS, BSIT (Computer Studies), BSECE (Engineering), BSN (Nursing). | 2026-10-25, Content population |
| 8 | May Applicants request a reschedule, not only Students? | Yes. Same Registrar approval path. | 2026-10-25, Reschedules |
| 9 | Should server code use the signed-in user's Supabase session, or keep `pg` and set `app.actor_id` per transaction? | The signed-in user's Supabase session, so row level security applies to real people. `lib/db.ts` stays only for system jobs with no signed-in person. See decision-log.md #10. | 2026-10-25, Auth and roles |
| 10 | Does "retry" on the Admissions side's "Send to Enrollment" button need its own Enrollment endpoint? | No. It calls the same intake endpoint again. Repeating a send is safe because the applicant ref makes it a refresh, never a second account. Admin's Resend in Enrollment re-runs the stored request of a rejected one. See decision-log.md #11. | 2026-10-25, Admissions intake |
| 11 | Build Admin's optional "tell Admissions the student is enrolled" callback now? | Built after the COR (features/admissions-callback). Enrollment tells Admissions when a student gets a student number (stage `student`) and when the COR is issued (stage `enrolled`). It is best effort, never blocks the Registrar, and a missed update is kept in `admissions_status_queue` and sent again when the Registrar opens the Documents or COR page. Needs `ADMISSIONS_STATUS_URL` and `ADMISSIONS_STATUS_SECRET`; it does nothing until both are set. | 2026-10-25, Admissions intake (built 2026-10-25) |
| 12 | Does the Admissions side also need to be built (applicant ref, outbound call, shared secret, retry button)? | Yes, as its own piece of work in the Admissions repo, done after build step 5 and written to the contract in `features/admissions-intake/schema.ts`. An earlier sender was added and reverted in Admissions (commits 4774b27, 97d1572); it used an older contract with no name or email, so it must not be restored as is. Enrollment is built first and can be tested with a manual call. | 2026-10-25, Admissions intake |
| 13 | If the Dean or Registrar rejects a schedule, what happens? | It goes back to draft with a required reason. The Secretary fixes it and submits again. A Registrar rejection also clears the Dean's sign-off, so the Dean signs again. An approved schedule cannot be rejected. See decision-log.md #18. | 2026-10-25, Section scheduling |
| 14 | Who places a student into a section? | Automatic: first section of the program, year level 1, with a free seat. The Secretary or Dean can move a student at any time until the assessment slip is issued. See decision-log.md #19. | 2026-10-25, Section scheduling |
| 15 | What format and fields does the COR need, and is there a PLP template? | Yes. A real PLP Certificate of Registration (2nd year, 1st semester, 2025-2026) was provided on 2026-10-25. It has: the Office of the University Registrar header; Enrollment No., Student No., name, address, course, department, scholarship or grant; Enrollment Date, Curriculum, School Year and semester, Year Level, Student Type, Adjustment No.; a class schedule (subject, description, section, units, room, days, time, pay units, lecture and laboratory on separate rows, total units); an assessment of fees (tuition units times a rate, miscellaneous, laboratory, old account, current account, contract or petition subject, midterm and final due); a certification line, student and University Registrar signatures, an "Officially Enrolled" seal with term, and a legend for added subjects. Which of these Enrollment generates is decided in the step 11 plan. | 2026-10-25, Assessment slip & COR generation |
