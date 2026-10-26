# project-brief.md

---
## AI RULES — READ FULLY BEFORE ANY ACTION
---

1. Read this entire file first. If any section is blank → stop and ask.
2. Automate before building UI. Only surface controls when human judgment is required.
3. Uncertain mid-build → pause, state why, offer two directions, wait for input.
4. All decisions must serve the intent defined below. Flag conflicts, never override silently.
5. Before touching anything → map all connected files and dependencies first.
6. At each major milestone — before, not after — confirm direction with the human before continuing.

---
## PROJECT REFERENCE
---

**Project Name:**
Enrollment System (post-Admissions), for PLP

**The Problem:**
After an applicant is admitted (handled by a separate PLP Admissions system), there is no system to turn that admitted applicant into a finalized, numbered, enrolled student: receiving documents, scheduling visits, building class sections/professor loading, clearing payment where required, and issuing the assessment slip and COR.

**The Goal:**
Take a newly admitted applicant handed off from PLP Admissions and carry them through document receipt, auto-assigned student numbering, schedule/professor/room setup, optional payment clearance, and finalized enrollment (COR) — with role-based staff handling each step.

**Who It's For:**
- Admitted applicants (become Students once the Registrar marks their documents received)
- Registrar — receives documents, approves schedules, issues assessment slip and COR, handles reschedules
- Finance — clears payment where the course requires it, manages the payment toggle
- Dean — signs off on professor loading for their college, can do everything the College Secretary does
- College Secretary — the Dean's assistant; prepares sections/professors/rooms, advises
- Professors — view their assigned subjects and class lists
- Admin — full access to everything, including the Admissions connection, settings, and account management

**Automation Expectations:**
Automatic, no human input:
- Student number assignment, the moment the Registrar marks documents received (one-time, never editable, never reused)
- Applicant account creation and refresh when Admissions sends/resends applicant data
- Moving every affected student to a new slot during a mass reschedule
- Skipping the Finance step entirely when a course's payment toggle is off
- Notifying students ("Your next step" card + email) whenever their schedule, reschedule outcome, or stage changes

Requires human decision/confirmation:
- Registrar marking documents received
- College Secretary preparing sections/professors/rooms; Dean signing off on professor loading
- Registrar approving the schedule and issuing the assessment slip
- Finance recording payment
- Registrar issuing the COR
- Registrar approving/declining a student's reschedule request
- Registrar or Admin triggering a mass reschedule
- Admin toggling a course's payment requirement (Finance can also do this)

**What Done Looks Like:**
A newly admitted applicant sent from PLP Admissions can be received into Enrollment, scheduled for a visit, have their documents marked received (auto-assigning a student number), have their section/professors/room set and Dean-approved, have their assessment slip issued, have payment cleared if required, and have their COR issued — with every role restricted per the RBAC table in enrollment-plan.md, and every money/schedule/student-number change and every reschedule written to an audit log.

**What This Is NOT:**
- Not the enrollment slip (that stays on the Admissions side)
- Not yet for returning students — newly admitted students only until steps 19 to 22 of docs/step-18-returning-students-plan.md are built
- Not the Admissions system itself — Enrollment only receives applicant data from it via one secure HTTPS call; the two systems keep separate databases and logins
- Does not let students pick their own visit slot — staff/system assign it; students may only request a reschedule
- Does not include the Admissions Officer or Student Success Office as system users (they exist at PLP but are outside this system for now)

**Open Questions Before Starting:**
See open-questions.md — tech stack, project scale, hosting, and other build-level decisions are not yet answered in enrollment-plan.md and must be resolved before any code is written.
