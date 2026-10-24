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
| 2 | What format/fields does the COR need, beyond student number, section, professors, and payment status — is there an existing PLP COR template to match? | Assessment slip & COR generation | [ ] |
| 3 | Should Admin's optional future "tell Admissions the student is enrolled" callback be built now or deferred, since enrollment-plan.md marks it "Later, optional"? | Connection to PLP Admissions | [ ] |
| 4 | What does "retry" look like on the Admissions side's "Send to Enrollment" button — does Enrollment need a dedicated endpoint for manual resend, separate from the original webhook? | Connection to PLP Admissions | [ ] |
| 5 | Confirmed from inspecting the PLP Admissions codebase: it has no applicant reference number field (e.g. ADM-2026-000042), no outbound webhook/HTTP client code, and no shared-secret config anywhere yet. `enrollment_intent.php`'s `confirm_enrollment` action only flips a local `enrollment_intent` flag — it does not call out to anything. Does the Admissions side also need to be built/modified to send the webhook (applicant ref generation, outbound call, retry button, shared secret in its env), or is that being handled separately from this conversation? | Connection to PLP Admissions | [ ] |
| 6 | What should the "design gate" check on each change: fail the build when components hardcode colors, spacing, radius or fonts instead of using `styles/tokens.ts`, per ux-ui-guidelines.md? Or something else? | CI/CD setup | [x] See Resolved #2 |
| 7 | SonarQube: use SonarCloud (hosted; free tier only for public repos) or a self-hosted SonarQube server? Is the GitHub repo public or private? | CI/CD setup | [x] See Resolved #3 |
| 8 | Supabase CLI expects timestamped files in `supabase/migrations/`; the project has `db/migrations/0001_init.sql` and a `migrate` script pointing at a `db/migrate.mjs` that does not exist. Move to the Supabase CLI layout, or keep `db/migrations/` and write a custom runner? (Schema files need human approval.) | CI/CD setup | [x] See Resolved #4 |
| 9 | With production-only and auto-migrate on merge to main, which guardrails do you want: PR required with checks passing before merge, forward-only migrations, and a Supabase backup before each production migration? | CI/CD setup | [x] See Resolved #5 |
| 10 | What is the student number format (year prefix, length)? Today it is an 8 digit padded sequence in `generate_student_number()`. | Documents & numbering | [ ] |
| 11 | What are the 13 Admissions program codes, their names and colleges (including BSENT)? They are not seeded yet. | Content population | [ ] |
| 12 | Applicants get their visit slot before they become Students, but the plan lets only Students request a reschedule. Should Applicants be allowed to request one too? | Reschedules | [ ] |
| 13 | `lib/db.ts` connects with a superuser connection string, which bypasses row level security. Should server code use the signed-in user's Supabase session, or keep `pg` and set `app.actor_id` per transaction? | Auth and roles | [ ] |
| 14 | If the Dean or Registrar rejects a schedule, what happens? The schema only moves forward (draft, pending_dean, dean_signed, approved). | Section scheduling | [ ] |
| 15 | Which Admin or staff role places a student into a section: Secretary and Dean only, or automatically? | Section scheduling | [ ] |

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

---
