# Plan: Steps 18 to 23, Grades, prerequisites and returning students (plp-enrollment)

Status: **plan closed, nothing built.** Revised after your third round of answers (leave of absence wanted, built last) and a second search for PLP's own grading policy. The only open items are facts the Registrar has to confirm; they are settings, so they do not block any step. Everything else is settled, either by you or by taking my recommendation. Written against the Enrollment repo as uploaded on 2026-10-25.

## 1. Goal

A student who finished a term continues to the next one without starting over. The system keeps their grades, knows which subjects are passed, stops them from taking a subject whose prerequisite is not passed, and moves students who passed everything into the next term automatically. Anyone with an incomplete, failed or dropped subject goes to a short review list for their college instead of being moved silently.

### Scope change, flagged

`docs/enrollment-plan.md` ("Returning students come later") and `docs/project-brief.md` ("Not for returning students") both say newly admitted students only. This plan changes that. Those two lines are not edited until you approve this plan.

## 2. Your answers (settled)

Round 1:

| # | Question | Your answer |
|---|---|---|
| 1 | Where do grades live? | In this system. |
| 2 | How is pass or fail decided? | A setting Admin controls. Nothing hardcoded. |
| 3 | Automatic promotion only when everything is passed, the rest reviewed by hand? | Yes. |
| 4 | Which prerequisite rules? | Only "this subject needs that earlier subject". A page to set them up. |

Round 2:

| # | Your answer | What the plan does with it |
|---|---|---|
| 1 | Research PLP. Descriptive grades (Good, Very Good, 1.00 and so on) are only useful for filters and are set by Admin. The mark that matters is INC: that subject has to be retaken and the student waits until next year for it. | Decisions A, B and C. Rules run on four outcomes only. Descriptive grades never change a rule. A retake waits for the next term that offers the subject (decisions H and I). |
| 2 | The Professor and the Dean. Take my recommendation. | Decisions D and E. The Professor enters, the Dean approves, the Registrar posts. |
| 3 | Summer: both (its own subjects and retakes). Take my recommendation. | Decision I. |
| 4 | Credited subjects for transferees: take my recommendation. | Decision R. |
| 5 | Students do not see grades. | Decision S. No grades screen for students at all. |
| 6 | Prerequisite owner: you did not know. | Decision G. Recommendation taken. |

Round 3:

| # | Your answer | What the plan does with it |
|---|---|---|
| 1 | Research PLP for the open questions. | Section 3 and section 9. The grade table, the passing mark and the INC window are not published anywhere I can reach. They stay Admin settings. |
| 2 | You want leave of absence later on. | Decision U and **step 23**, built after step 22. |
| 3 | Staff record leave, students never file it. | Step 23. |
| 4 | Expired leave and the Registrar's role: recommendation requested, UX guidelines read. | Step 23: expiry is automatic and uses the existing review list, and the Registrar has no approval step, only a read-only list. |

## 3. What PLP does (research)

Sources: PLP's Registrar **Citizen's Charter 2024** (`assets.pasigcity.gov.ph`, sections 3, 7, 8, 9 and 5), which is PLP's own document. The same charter was used for the earlier steps.

What the charter says:

- **Incomplete (INC) is provisional.** The INC must be removed within two weeks after semestral grades are submitted. The final grade is then the combined midterm and completion grade. **If it is not removed, the grade becomes 5.0, Failure.** Completing it is a form signed by the faculty member, signed by the College Dean, then recorded by the Registrar's Grades Processing Officer.
- **Enrollment of an old student.** The student brings the previous semester's grade report. The **College Dean screens who is eligible**, advises the subjects, and issues the assessment slip. Finance clearance is only for students with a balance and for AB Psychology. The Registrar prints the COR.
- **Enrollment of a new student.** The Dean "tags the curriculum", which is the step where a transferee's earlier subjects are placed.
- **Dropping.** An official drop (an "OD" remark) is applied for at least two weeks before midterm exams, signed by the professor and the Dean, then processed by the Registrar.
- **Adjustment of registration.** Add, delete or change a course or schedule within the first week of classes, signed by the professors and the Dean, recorded by the Registrar.
- **Leave of absence.** Up to one academic year, at most two, approved by the Dean. The student's account is deactivated and a readmission slip is issued.

Second search (round 3): PLP's own website was not reachable from here, and searches returned only other schools' handbooks (PLM, PLMun, UP, PUP) and third-party grade tables. **No PLP grade table, passing mark, INC deadline or finance-clearance rule is published where I could read it.** The charter section on leave of absence is the only PLP source, and it is the basis for step 23.

What I did **not** find: PLP's own numeric grade table or passing mark. The charter only names 5.0 as Failure. The widely used national convention (1.00 best, 3.00 lowest passing, 5.00 failed) appears on several third-party sites, and one old third-party conversion list puts PLP in the group that uses it, but none of that is PLP's own document, so **nothing is seeded**. A different university's handbook (Pamantasan ng Lungsod ng Muntinlupa) gives a one-year INC window. It is a different school and is not used.

## 4. What exists today (found in the code)

The system was built for one enrollment per student, ever. This is the main thing that makes the plan large.

- **One of everything per student.** `student_sections.student_id` is the primary key. `assessment_slips`, `payments` and `cors` each have `student_id UNIQUE`. A second term for the same student is refused by the database.
- **No term on sections.** A section is unique by `(program, year_level, name)` with no school year or semester, so it cannot be reused for the next term.
- **No semester on subjects.** `subjects` has `program_id` and `year_level` only. A new section takes every subject of its year level, so the seeders load one semester per year level and say so (`05_bsit_subjects.sql`, `optional/bsit_year1_2nd_sem.sql`).
- **One current term.** `enrollment_term` is a single row Admin edits (school year, 1st, 2nd or summer). A COR copies it when issued. Nothing else knows about terms.
- **Placement is Year 1 only.** `place_student_in_section` takes the first Year 1 section with a free seat. A transferee who belongs higher is moved by hand.
- **A student's schedule comes from their one section.** The slip, the COR, `student_schedule_json`, the professor class lists and the seat counts all read `student_sections` and the section's subjects.
- **Professors can only read.** No role writes grades, and no table holds them.
- **No prerequisites, no grade, no pass or fail** anywhere in the schema.
- **Withdrawal** (`withdraw_enrollment_core`) deletes the student's section seat and pending payment. It assumes one enrollment.
- **The schedule approval chain** (Secretary prepares, Dean signs, Registrar approves, decision #4) and the catch-up pattern that runs on page load (`catchUpAdmissionsStatus` on the Documents page) both exist and are reused below.

Features that read these tables and change with it: `assessment-slip`, `cor`, `payment`, `section-scheduling`, `next-step-card`, `dashboards`, `withdraw-enrollment`, `search`, and the professor home.

## 5. Decisions

| # | Question | Decision | Status |
|---|---|---|---|
| A | Grade scale | A **settings table of bands**, edited by Admin on a Grading tab. Each band has a label, an **outcome** (`passed`, `incomplete`, `failed`, `dropped`), and for numeric grades a from and to value. The system never assumes whether a high or low number is better: the bands say it. **Descriptive bands** (Excellent, Very Good, Good, or 1.00 to 1.25 and so on) are optional, carry the outcome `passed`, and exist only for display and filters. They never change a rule. Nothing is seeded (section 3). Grade entry stays disabled until Admin saves a scale, and says so. | Settled by you, shape is a proposal |
| B | What each outcome does | Only `passed` satisfies a prerequisite. `incomplete`, `failed` and `dropped` all block the subjects that depend on it and send the student to the review list. A grade of 5.0 and an INC that was never completed are the same thing to the rules. | Settled by you and the charter |
| C | INC lifecycle | An INC is provisional. Completing it needs a grade change (decision E) within the window. **If the window passes, the system turns it into a failed 5.0 by itself, with no button.** The window is a setting in days, default **14**, from the charter. The lapse runs when the Registrar's or Dean's Grades page loads and when a term is closed, the same catch-up pattern the Documents page uses. | Settled by research, window length needs the Registrar to confirm |
| D | Who enters and approves grades | The **Professor** of a section subject enters the grades and submits. The **Dean of that college approves**, which locks them. The **Registrar posts** by closing the term. Admin can do any step, as everywhere. | Settled by you and recommendation |
| E | Changing an approved grade, completing an INC, recording an official drop | One path for all three, mirroring the schedule chain and charter section 8: the **Professor proposes** the new result with a reason, the **Dean signs**, the **Registrar approves**. No role edits an approved grade directly. Audit-logged, with who, what, when and why. | Settled, recommendation taken |
| F | Prerequisite model | A subject lists the earlier subjects that must be **passed**. All listed ones are required. No "either one" rules, no year-standing rules, no co-requisites. Any passing attempt counts, so a retake that passes unblocks the student. The setup page refuses a subject in another program, a subject that is not earlier in the curriculum (lower year, or the same year and an earlier semester), a subject that requires itself, and any loop. | Settled by you, details proposal |
| G | Who sets prerequisites | **Admin and the Dean of that college** (the charter has the Dean tagging the curriculum, and Admin has every permission). The Registrar and Secretary can view. The subjects themselves stay Admin only (decision #26). | Settled, recommendation taken |
| H | Semester on subjects | Add `semester` (`1st`, `2nd`, `summer`) to `subjects`: the term when a regular student takes it. A section takes only the subjects of its year level and semester. This is also what makes a retake wait: a failed 1st semester subject is offered again in the next 1st semester term. | Proposal, needed |
| I | Summer | Summer carries **both** retakes and its own subjects. Admin flags which subjects are offered in summer (a flag on the subject, so a normal 1st semester subject can also run in summer). Summer is **never part of automatic promotion**: a student takes it only through a load built by the Secretary or Dean. A summer pass counts like any other, so a retake does not have to wait a year when the subject runs in summer. | Settled, recommendation taken |
| J | Terms on sections | Every section belongs to a school year and semester. Each term gets **its own sections**, created by copying the previous term's sections (same names, capacities and subjects, no professors, rooms or times). The Secretary then does the usual loading. | Proposal |
| K | Enrollment per term | One **enrollment** per student per term, holding the section and year level. `student_sections`, `assessment_slips`, `payments` and `cors` become one per student **per term**. The student number stays the same forever. | Proposal, large |
| L | Per-student subject list | Every enrollment gets its own subject list. A regular student's list is copied from their section automatically. A subject blocked by a non-passed prerequisite is left out. A retake or back subject is added by the Secretary or Dean. This is the per-student list that the step 16 plan (decision B) left for later. | Proposal, own step |
| M | Which students are promoted automatically | Only when **every counted subject of the term has outcome `passed`**. They are placed in the next term's section with free seats. Next term is the next regular semester: 1st goes to 2nd of the same year, 2nd goes to 1st of the next year. | Settled by you, rules proposal |
| N | Everyone else | Goes to a **needs review** list for the Secretary or Dean of their college, who build the load. Nobody is moved silently. This is the charter's "Dean screens who is eligible" step. | Settled by you and the charter |
| O | Last semester of the last year | A program's last year is the highest `year_level` that has subjects in the catalog. A student who passes it is marked **completed**, gets no next section, and appears in a Registrar list. Graduation itself is not built. | Proposal |
| P | Closing a term | One control for the Registrar or Admin: **Close term**. It is disabled until every section subject has Dean-approved grades, and names what is missing. Closing runs the INC lapse, builds the review list, and promotes the regular students. | Proposal |
| Q | The returning student's path | No visit, no documents, no Admissions handoff. Schedule, slip, payment (only if the program toggle is on), COR, with the same Registrar and Finance steps as today. The charter also clears students **with a balance**. Balances are not tracked in this system and are not built. | Proposal |
| R | Credited subjects for transferees | The **Dean (or the Secretary) records a credit** with a reason that names the line of the transferee's TOR. The **Registrar approves** (same chain as decision E). A credit has outcome `passed` and source "credited", no grade number. It satisfies prerequisites and is not counted in the promotion check. | Settled, recommendation taken |
| S | Students and grades | **Students do not see grades anywhere in this system.** A student on the review list sees a plain line on their next step card to go to their college for advising, as the charter says, with no grade shown. | Settled by you |
| T | Withdrawn and dropped | A withdrawn student is excluded from promotion and the review list. Withdrawal records `dropped` for that term's subjects and releases only the **current** term's seat. An official drop of one subject is a grade change (decision E). | Proposal |
| U | Leave of absence | **Built as step 23, after step 22.** Follows the charter: up to one academic year at a time, two at most, Dean approves, the student's account is deactivated, and a readmission slip is issued on return. The system does the deactivation and the slip, with no extra approver (UX rule: no control where no human judgment is needed). Until step 23, the only guarantee is that a student with no enrollment in the closed term is neither promoted nor listed as failed. Details in step 23. | Settled by you, details recommendation |

### Decisions this touches (flagged, not overridden)

- **#4** (three gates for a schedule): unchanged for the first approval of each term's sections. Decision E reuses the same three-step chain for grades.
- **#19** (placement in Year 1 only, a student cannot be moved after the slip): placement becomes year-aware. The lock after the slip stays, now per term.
- **#21** (a COR keeps the term it was issued in): kept. There will now be one COR per term.
- **#26** (subjects are Admin content): kept. Semester, the summer flag and prerequisites are added to that content. Decision G lets the Dean edit prerequisites for their own college, which is the one widening.
- **Step 16's decision B** (no per-student subject changes): built in step 22.
- **Step 7's decision G** (a correction goes through staff with a reason): grade changes follow the same idea.
- **Decision-log entries needed:** the grade scale and outcomes, enrollment per term, prerequisites, grade approval and changes, automatic promotion with the review list, and leave of absence.

## 6. Build in six steps

Each step ends in something that can be checked and is ticked on its own. Steps 18 and 19 change nothing a current student sees. Step 23 is last and can wait.

### Step 18. Terms foundation

Makes a second term possible. No new screen.

- `subjects.semester` and the summer flag, and a school year and semester on `sections`. Section uniqueness and the automatic subject fill (`after_section_created`, `add_subject_to_draft_sections`) become term-aware.
- An `enrollments` table, one per student per term. `student_sections`, `assessment_slips`, `payments` and `cors` become one per student per term.
- Existing rows are backfilled into the current term. `cors` already carry a term; slips and payments take the current term.
- Replaced functions, each rewritten from its latest version with one added term filter: placement, `move_student_section`, `assessment_slip`, `student_schedule_json`, `certificate_of_registration`, `issue_cor`, `issue_all_ready_cors`, `record_payment`, `payment_queue`, `my_payment_status`, `withdraw_enrollment_core`, the professor class list view, and the next-step and dashboard queries.
- The seeders stop carrying the "one semester per year" workaround and tag each subject with its semester.
- Acceptance: every existing check in `supabase/gates_check.sql` still passes, and a new check proves one student can hold a slip, payment and COR in two different terms.

### Step 19. Grading scale and grades

- **Grading tab** on the Admin Content page (next to Subjects, Rooms and Term): the bands, and the INC window in days.
- **Professor Grades page:** enter and submit grades for a section subject.
- **Dean Grades page:** the college's section subjects awaiting approval. Approving locks them.
- **Registrar Grades page:** every section subject with its status, and a Changes tab for grade changes awaiting approval (decision E).
- Grade rows record the term, the outcome copied from the band at the moment of entry (so changing the scale later never rewrites history), who entered it, who approved it, and when.
- No student view (decision S).
- Acceptance: a grade resolves to one outcome. Overlapping or gapped numeric bands are refused when Admin saves the scale, naming the two bands. A Professor cannot change a grade after the Dean approves it. A grade change needs a reason and all three signatures. An INC older than the window becomes a failed 5.0 without anyone acting.

### Step 20. Prerequisites and credits

- **Prerequisites page** for Admin and the Dean (decision G). The Dean sees and edits only their college's programs.
- A database function that answers, for a student and a subject, whether they may take it and which prerequisite blocks them. It is the one definition of eligibility, used by steps 21 and 22.
- **Credits** (decision R): a Credits control on a student row inside the existing section details window for the Dean or Secretary, and an approval for the Registrar.
- Acceptance: a subject whose prerequisite is incomplete, failed, dropped or never taken reports as blocked with the prerequisite named. A passed prerequisite, a passing retake or an approved credit unblocks it. Deleting a subject that others require is refused with the dependents named. A Dean cannot edit another college's prerequisites.

### Step 21. Close term, review list and automatic promotion

- **Close term** control for the Registrar or Admin (decision P), on the Registrar's Grades page.
- Opening the next term (Admin sets it in the existing Term tab) creates the next term's sections by copying the previous term's, then places the regular students automatically (decisions J and M).
- The **needs review** list for the Secretary or Dean, as a tab on the existing Schedules page, scoped to their college, with the reason on each row (for example "INC in COMP 104"). A completed-students list for the Registrar.
- The returning student's next step card uses the states that already exist, plus the one advising line (decision S).
- Acceptance: closing is refused while any section subject lacks Dean-approved grades. A student who passed everything is placed in the right next section with a notification. A student with any non-passed subject is on the review list and not placed. A student who passed the last semester of the last year is marked completed. Closing twice is refused. Withdrawn students and students with no enrollment in the term are skipped.

### Step 22. Irregular loads

- A per-student subject list on each enrollment (decision L). Regular students keep getting their section's subjects with no work from staff.
- On the review list, the Secretary or Dean opens a student and sees every subject by eligibility: allowed, blocked with the prerequisite named, already passed, or not offered this term. They add a retake or back subject from any section of that term that offers it. A first semester subject that was not passed cannot be added in a 2nd semester term.
- The slip, COR, schedule JSON, class lists and seat counts read the per-student list instead of the section's subjects. Seat counts become per section subject instead of per section.
- A section schedule change (step 16, `amend_schedule`) notifies everyone enrolled in that section subject, not only the section's students.
- Acceptance: a student blocked on one subject is not offered it and still gets the rest. A retake from a lower year appears on their slip and COR with its own section, professor, room and time, and in that professor's class list. A subject cannot be added if its prerequisite is not passed, even by Admin.

### Step 23. Leave of absence and readmission

Built last, once terms, grades and the review list exist. Nothing in steps 18 to 22 changes shape for it.

- A **leave** record per student: start term, length in terms, reason, and a status (`requested`, `approved`, `active`, `ended`, `rejected`). Length is capped at one academic year per leave and two in total (charter). The system counts the student's approved leave and refuses a third year.
- **Who does what:** the Secretary or Dean records the request with the reason. Students never file it (settled). The **Dean approves**, and that is the only human decision. The Registrar has **no approval step and no control**, only a read-only list. Grade changes need three signatures because they alter the official record. A leave needs one judgment, the Dean's, so a Registrar confirmation would be a button with nothing to decide.
- **Deactivation is automatic.** The account is deactivated by the system when the leave's first term opens, not when the Dean approves, because the student may still be finishing the current term. It is reactivated automatically when the Dean builds the returning load. The readmission slip is issued by the system at that moment.
- **Timing:** a leave starts at a term boundary only. A student who leaves mid-term is withdrawn from that term's subjects through the existing withdrawal path (decision T) and the leave starts at the next term. This keeps grades and promotion simple.
- **While on leave:** the student is skipped by Close term, promotion and the review list, and shown in a Registrar list of students on leave with their return term.
- **Return:** when the leave ends the student is **not** placed automatically. They appear on the needs review list as "returning from leave", the Dean builds the load (charter: the Dean screens and advises), the account is reactivated, and a readmission slip is issued. Prerequisites and earlier grades apply as they stand.
- **Expiry is automatic and has no new screen.** When a leave's end term opens with no return, the system marks it `ended` and adds the student to the existing needs review list with the reason "leave ended". There is no dismiss button and no new list. A student who reaches the two-year cap appears on the same list with the reason "two years of leave used"; the Dean decides what happens next outside this system. Nobody is dropped or removed automatically. The check runs when the Schedules page loads and when a term opens, the same catch-up pattern as the INC lapse.
- Acceptance: a Dean cannot approve a leave beyond the cap. A student on leave is not promoted or listed as failed when the term closes. A returning student is never placed without the Dean's load. The account is deactivated by the system when the leave's first term opens and reactivated when the load is built. An ended leave appears on the review list without anyone acting. Everything is audit-logged with who, what, when and why.

## 7. UI and UX (ux-ui-guidelines.md)

Read in full again for this revision. The required inspiration search (2 to 3 reference examples per new screen) was **not done**, because this is a plan. It is done, and shown to you, before each screen below is built.

**Flow type.** The existing multi-section staff app with the left sidebar, and the student's linear flow with no sidebar. No new navigation pattern.

**Automation first.** These need no control: copying sections for a new term, placing regular students, building the review list, resolving a grade to its outcome, turning a lapsed INC into 5.0, checking prerequisites when a load is built, notifying students. The human controls are only: entering grades, approving grades, proposing and approving a grade change, setting the scale, setting prerequisites, recording a credit, closing a term, and building an irregular load.

| Screen | Who | Where | Pattern |
|---|---|---|---|
| Prerequisites | Admin, Dean | New sidebar item for each | A program filter, then one row per subject with its prerequisites as text. Fewer than 5 rows is a list, 5 or more a table. **Edit** opens a centered modal with a multi-select of the earlier subjects of that program. Primary action bottom right. The Dean's list is limited to their college. |
| Grading | Admin | New tab on the Content page | A short list of bands, one row each (label, outcome, from, to), and the INC window. Edit in a centered modal. Save is disabled while bands overlap, and names the two. |
| Grades | Professor | New sidebar item | One section subject at a time (a select at the top). One row per student, one grade field per row, the resolved outcome as a text pill with a tinted background and no dot or border. **Submit grades** bottom right, disabled until every row has a valid grade, naming the first missing student. |
| Grades | Dean | New sidebar item | List of the college's section subjects awaiting approval, then the rest. Opening one shows the grades read only with **Approve** bottom right. Grade changes awaiting the Dean's signature sit in a Changes tab. |
| Grades | Registrar | New sidebar item | List of section subjects with status (Not submitted, Submitted, Approved). Tabs: Sections and Changes. **Close term** is one control on this page, disabled with the missing section subjects named. |
| Needs review | Secretary, Dean | New tab on the existing Schedules page | List of students with the reason, **Open** per row. The load builder is a centered modal if it fits one screen, otherwise a full page. |
| Leave of absence | Secretary, Dean | A control on a student row in the section details window | Small centered modal to record (reason, first term, length in terms). The Dean approves from the existing Changes tab. Expired leaves use the existing needs review list. The Registrar gets a read-only list of students on leave with the return term, as a tab on the existing Grades page, with no control. |
| Credits | Dean, Secretary | A control on a student row in the existing section details window | A small centered modal: subject, reason. The Registrar's approval lives in the Registrar's Grades Changes tab. |

- **Labels.** One label per concept. The sidebar says Grades, so the page title is Grades with no subtitle. Professor, Dean and Registrar each have a Grades page, which is fine because they are different roles and never share a screen.
- **Icons.** The project uses Heroicons (24 outline) through `components/NavIcons.tsx`. Proposed: `AcademicCapIcon` for Grades. Prerequisites has no established symbol, so it is **your call**: `LinkIcon` is the closest, or no icon and a text label only. No icon is hardcoded.
- **States** defined for every control: default, hover and focus, loading, success, error with the specific database message, empty, and disabled with the missing item named. The grade entry rows also show a per-row error for a value that matches no band.
- **Tables and lists.** Fewer than 5 rows is a list. A table is never placed inside a card. No stat cards. Each Grades page orders what needs action first.
- **Typography, spacing, radius, padding.** Tokens only (`styles/tokens.ts`), so the design gate passes. No new token is proposed.
- **Responsive.** Staff pages are desktop first, as today. Grade entry is the one screen a professor might use on a phone, so its rows stack (name above the field) at the narrow width. To be checked when built.
- **Copy.** Plain wording, no exclamation marks, no emoji, realistic sample data (BSIT subjects from the existing seeders).

## 8. Acceptance criteria for the whole feature

- Nobody types a pass or fail: the scale decides it, and a change to the scale never rewrites a grade already recorded.
- A grade is not final until the Dean approves it, and no one edits it afterwards except through a grade change with a reason and all three signatures.
- An INC that is not completed within the window becomes a failed 5.0 on its own.
- A student cannot be loaded into a subject whose prerequisite they did not pass, by any role.
- A student who passed every subject is in the next term's section without anyone pressing a button for them.
- A student with any incomplete, failed or dropped subject is on the review list and nowhere else until staff act.
- A subject that was not passed is only offered again in a term whose semester offers it (summer included, if flagged).
- One student can hold a slip, a payment and a COR in each of several terms, and each document keeps what it showed when issued.
- Every grade entry, approval, change, scale change, prerequisite change, credit, term close and promotion is in the audit log with who, what, when and why.
- A student on leave is skipped by promotion and the review list, and returns only through a Dean-built load (step 23).
- A Professor sees and edits only their own sections. A Dean or Secretary sees only their college. A Student sees no grades.
- Existing slips, CORs, payments and sections still open after step 18.
- The pages pass lint, type check and the design gate in CI, and the migrations pass `supabase db reset` and `db lint` in CI.

## 9. Risks and open items

Still to confirm with the Registrar. None of these blocks a build step, because each one is a setting Admin enters:

| # | Question | Gates |
|---|---|---|
| 1 | PLP's real grade bands and passing mark. I searched twice and found no PLP document. Admin enters them from the Registrar's grading policy. | Entering the scale in step 19, not building it |
| 2 | The INC window. The charter says two weeks after grades are submitted. It is a setting in days. | Same |
| 3 | Unpaid balances and Finance clearance for old students. No balances in this system. Later, if wanted. | Not gating |

Resolved this round: leave of absence is wanted and is step 23.

Risks:

- **Step 18 is the riskiest and the least visible.** It changes the uniqueness rule on four tables and rewrites about a dozen functions that all assume one enrollment. Every existing check must pass before step 19 starts.
- **Curriculum has to be entered first.** Prerequisites, promotion, the retake wait and the "last year" rule all depend on the catalog having every year and semester of each program. Today only BSIT Year 1 and Year 2 (1st semester) are seeded, and the real catalog is still to be entered by Admin (decision #26).
- **Backfill.** Existing slips and payments have no term. They are assigned the current term, which is correct only while every student is in their first term.
- **Seat counts change meaning in step 22.** A seat in a section and a seat in one subject of a section are different once a student can take a single subject from another section.
- **A grade change after promotion.** If an approved grade changes after a student was promoted, the placement is not undone. The approval tells the Registrar the promotion no longer matches, and the Secretary or Dean fixes the load by hand.
- **The INC lapse is lazy.** It runs when a Grades page loads or a term closes, not on a timer. A student's status can therefore be a few hours behind the deadline. Prerequisite checks run the lapse first, so a rule never uses a stale INC.
- **Pending emails** pile up until the sender session, like every earlier step.

## 10. Not in this plan

- Graduation, diplomas, honors and clearance.
- Grade point average, Dean's list and transcripts.
- Students seeing grades (decision S).
- Students filing leave themselves (staff record it, step 23).
- Unpaid balances and Finance clearance for old students (decision Q).
- Shifting to another program.
- Year-standing rules, co-requisites and "either subject" prerequisites.
- Fee amounts per term or per unit (the payment step is unchanged).
- Letting a student enroll themselves, or pick their own subjects.
- Telling Admissions anything about returning students.
- Sending the emails.

---

## As built (phase 1, step 18)

- `student_sections` is kept as the enrollments table, with the term on each row (decision #31), instead of a new table.
- A COR takes the term of the student's enrollment, not the current term.
- A section can only be created when the term is set.
- Admin sets a subject's semester and summer flag in Content.
- Not done: the dashboard funnel still counts rows. Nothing was run.

## As built (phase 3, step 20)

- Writes to `subject_prerequisites` and `student_credits` go only through the functions. A trigger refuses any other write, Admin included, like the grading tables (decision #33).
- The Registrar and the Secretary get their own read-only Prerequisites pages (`/registrar/prerequisites`, `/secretary/prerequisites`). Admin and the Dean edit on `/admin/prerequisites` and `/dean/prerequisites`. All four share one view.
- The Registrar approves or rejects a credit under Grades, tab Changes, beside the grade changes. There is no new page and no new count on the home list.
- Credits are recorded from the section details window, so a student appears there only while placed in a section. A student still waiting for a section cannot be given a credit yet; step 22's review list is the natural place.
- Eligibility reads approved grade sheets only. The check is read-only, so it does not run the INC lapse first (the plan said it would). A lapsed incomplete that has not been turned into a failed 5.0 yet still blocks, so the answer differs only in the label shown.
- The loop check in `save_prerequisites` cannot be reached while a prerequisite must be strictly earlier in the curriculum. It stays as a guard in case a year level or semester is ever editable.
- Not done: the eligibility answer is not used anywhere yet (steps 21 and 22). The audit labels for the step 19 tables (`grade_bands`, `grade_sheets`, `grades`, `grade_changes`, `grading_settings`) are still missing from `features/audit-log/schema.ts`. Nothing was run.
