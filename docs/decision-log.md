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
