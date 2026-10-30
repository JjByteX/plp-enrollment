// features/user-manual/content.ts
//
// The staff user manual, kept as plain markdown text. parse.ts turns it into
// blocks and ManualView.tsx draws them with the design tokens. To change the
// manual, edit the text below; no component needs to change.

export const MANUAL_SOURCE = `# PLP Enrollment: User Manual

For staff of Pamantasan ng Lungsod ng Pasig.

Use this manual to look up what a page does, the steps from "admitted" to "enrolled", and what to do when something goes wrong.

### Where to start

| Your role | Read |
|---|---|
| Everyone | [Getting started](#2-getting-started), [The whole journey](#3-the-whole-journey-from-start-to-end) |
| Registrar | [Registrar pages](#5-page-by-page-registrar), [Reschedules](#7-reschedules), [Withdrawals](#8-withdrawals), [Closing a term](#9-grades) |
| College Secretary or Dean | [Secretary and Dean pages](#6-page-by-page-college-secretary-and-dean), [Prerequisites and credits](#6-page-by-page-college-secretary-and-dean), [Leave of absence](#6-page-by-page-college-secretary-and-dean), [Grades](#9-grades) |
| Finance | [Finance pages](#10-page-by-page-finance) |
| Professor | [Professor pages](#11-page-by-page-professor), [Grades](#9-grades) |
| Admin | [Admin pages](#12-page-by-page-admin), [Setup checklist](#14-before-the-first-day-setup-checklist-admin) |
| Something looks wrong | [When something looks wrong](#15-when-something-looks-wrong) |

---

## 1. What this system is

PLP Enrollment starts after a student is admitted in the PLP Admissions system. A student goes through these steps:

1. Get a visit date.
2. Bring original documents to the Registrar.
3. Get a student number.
4. Get a class schedule (section, professors, rooms).
5. Get an assessment slip.
6. Pay, but only if the course requires it.
7. Get the COR (Certificate of Registration). The student is now enrolled.

Each step belongs to one office. The system does not let anyone skip a step or do another office's step.

### Who uses it

| Role | What they do in short |
|---|---|
| Applicant | A newly admitted person who has not yet submitted documents. Sees their next step. |
| Student | An applicant whose documents were received. Sees their number, schedule, slip and COR. |
| Registrar | Runs visits, receives documents, approves schedules, issues slips and CORs, handles reschedules, closes the term. |
| Finance | Records payments and decides which courses need payment. |
| Dean | Signs off professor loading for their own college, approves grades, decides leaves of absence. Can do everything the College Secretary can do. |
| College Secretary | Prepares sections, professors, rooms and times for their own college. |
| Professor | Sees their classes and class lists. Enters grades. |
| Admin | Can do everything. Also manages accounts, subjects, rooms, the school term, the grading scale and the Admissions connection. |

You only see the pages for your role. A page that is not yours will not open.

---

## 2. Getting started

### Signing in

1. Open the system and go to the sign-in page.
2. Type your email and password.
3. Press **Sign in**. You land on your own home page.

Common messages:

- **"Email or password is wrong."** Check your typing and try again.
- **"Too many attempts."** Wait a few minutes.
- **"This account has no access to PLP Enrollment."** Your account is switched off. Contact the Admin. A student's account is also switched off while an approved leave of absence is running, and switched back on when the college places the student in a section again.

There is no public sign-up. Staff accounts are made by the Admin. Applicant accounts are made automatically when Admissions sends the person over.

### Setting your password for the first time

When an account is created, the person gets an email with a **Set password** link.

1. Click the link in the email.
2. Type a new password (at least 8 characters) and type it again to confirm.
3. Press the button to save. You go straight to your home page.

If the page says **"This link has expired or was already used"**, ask the Admin to send a new one.

### Finding your way around

- **Sidebar (left):** your pages. It can be collapsed with the small arrow button.
- **Search bar (top):** press the **/** key, then type at least 2 letters. It finds pages and records (for example a student's name or number). You only get results you are allowed to see.
- **Profile menu (top right, your name):**
  - **Settings:** make the text bigger or smaller and switch between light and dark look.
  - **Withdraw enrollment:** only for Applicants and Students (see [section 8](#8-withdrawals)).
  - **Sign out.**
- **Home page:** staff homes show a list of your pages with a **"N waiting"** tag. Pages with work to do are shown first.

---

## 3. The whole journey, from start to end

The steps for one student, in order.

### Step 1: Admissions sends the applicant

When the applicant confirms enrollment in Admissions, Admissions sends their details here. Nobody types anything.

The system then, by itself:

- Creates the applicant account (or updates it if the same person was sent before).
- Books the earliest open visit slot for the applicant's program.
- Sends the applicant an email with a link to set their password.

If no visit slot is free, the applicant shows up as "waiting for a visit" and the Registrar adds a slot (Step 2).

### Step 2: Visit date

The student never picks their own date. The system or the Registrar assigns it. The applicant sees the date, time, office and the list of what to bring on their **Your next step** card.

### Step 3: Documents received and student number

The student comes with original documents. The Registrar ticks each one on the checklist and then presses **Mark documents received**. At that moment:

- The system gives the student a number, like **26-00001** (year, then a 5 digit counter that starts again each year).
- The applicant becomes a Student.
- The visit is marked as attended.
- The system tries to put the student in a section right away.

The number is final. It cannot be edited and is never reused.

### Step 4: Schedule

The College Secretary prepares the section: professor, room, day and time for every subject. The Dean signs off the professor loading. The Registrar approves. Students in the section can then get their assessment slip.

### Step 5: Assessment slip

The Registrar issues the slip once the student's section schedule is approved.

### Step 6: Payment (only if the course requires it)

If the student's course has payment turned on, Finance records the payment. If payment is off for the course, this step is skipped completely.

### Step 7: COR

The Registrar issues the COR. The student is now officially enrolled for the school year and semester.

### What the student sees along the way

Every Applicant and Student page has a **Your next step** card. It always tells them what to do next. Examples:

- "Waiting for your visit schedule."
- The visit date, time, office and what to bring.
- "Your documents were received. Your student number is 26-00001."
- "You are placed in BSIT 1A. Your college is preparing your schedule."
- "Your assessment slip is ready. Next, Finance clears your payment, then the Registrar issues your COR."
- "You are officially enrolled."

Their home page also shows a step bar: Visit, Schedule, Assessment slip, Payment (only if required), COR.

### Later terms

After the first term, the same steps repeat for each term. The Registrar closes the term, the Admin opens the next one, and students who passed every subject are moved up to the next term by the system. Students who did not pass everything, and students coming back from a leave of absence, wait on the **Needs review** list until the Secretary or Dean builds their load. They then get a new assessment slip, payment if required, and a new COR, as in steps 5 to 7. See [Closing a term](#9-grades), [Building a load for a student who needs review](#6-page-by-page-college-secretary-and-dean) and [Leave of absence](#6-page-by-page-college-secretary-and-dean).

---

## 4. Page by page: Applicants and Students

### Home

Shows the step bar. All details and buttons are on the **Your next step** card.

### Your next step card

- Before a visit date: tells them to wait for the Registrar.
- With a visit date: shows the date, time, office and what to bring. It also has a **Request a reschedule** button (see [section 7](#7-reschedules)).
- After documents are received: shows the student number, section, schedule status, slip, payment status and COR status. It lists any document still to be submitted later (for example Form 137).

### Assessment slip page

Open it with **View assessment slip** on the card. It shows student number, name, program, section, each subject with professor, room and time, total units, and whether payment is required. Press the print button to print it or save it as a PDF.

### COR page

Open it with **View COR** on the card once enrolled. It shows the schedule, the payment details if payment was required, and "Officially enrolled" with the school year and semester. It can also be printed or saved as a PDF.

### Readmission slip

A student who comes back from a leave of absence gets a **View readmission slip** link on the **Your next step** card once the college has placed them in a section. The slip shows the leave, the term they were readmitted to, who approved the leave and who built the load, and it can be printed. It does not show the reason for the leave. The assessment slip and the COR follow as usual.

### Withdraw enrollment

Found in the profile menu. See [section 8](#8-withdrawals).

---

## 5. Page by page: Registrar

Sidebar: [Home](/registrar), [Visits](/registrar/visits), [Reschedules](/registrar/reschedules), [Documents](/registrar/documents), [Schedules](/registrar/schedules), [Slips](/registrar/slips), [COR](/registrar/cors), [Grades](/registrar/grades), [Prerequisites](/registrar/prerequisites).

### Home

- The list of your pages with how many are waiting on each.
- **Enrollment funnel:** how many people reached each stage (Admitted, Documents received, Placed in a section, Assessment slip issued, Enrolled) and where most people get stuck.
- **Visit capacity:** open seats on the coming days, compared with how many applicants still have no date.
- **Schedule pipeline:** how many sections are in Draft, Waiting for Dean, Waiting for Registrar and Approved.

### Visits

Use this page to set up visit slots and make sure everyone has a date.

**Filters:** choose a Program and/or a Date.

**New slot:** press **New slot** and fill in Program, Date, Start time, End time, Capacity (how many people), Office, and Extra notes (optional, shown after the standard list of documents to bring).

Rules:

- The date cannot be in the past.
- The end time must be after the start time.
- Capacity cannot be lowered below the number already booked.
- Once someone is booked, you can no longer change the slot's program, date, time or office.
- A slot with people booked cannot be cancelled. You can close it instead.

**Waiting for a visit:** choose a program to see applicants who have no date yet. Pick a slot beside a name and press the button to assign them, or press **Assign all unassigned** to fill the earliest open slots in order of admission date.

**Slots table:** each row has these buttons.

- **View:** see who is booked. You can move a person to another slot. You must type a reason.
- **Edit:** change slot details (within the rules above).
- **Close:** stop new people from being booked. **Reopen** undoes it.
- **Cancel:** removes an empty slot for good. A cancelled slot cannot be reopened.

### Reschedules

Two tabs. See [section 7](#7-reschedules) for the full story.

- **Requests:** reschedule requests from applicants and students waiting for your answer.
- **Mass reschedule:** move everyone on a date to a new date (typhoon, class suspension, office closed).

### Documents

Three tabs: **Waiting**, **Received**, **Withdrawn**. Use Search (name, reference or email) and the Program filter.

**Waiting tab:** applicants who are not students yet.

1. Open a person. A checklist appears, made for their admission type (New, Transferee or Foreign).
2. Tick each original document you received. For "Other document", a note is required.
3. When every required document is ticked, press **Mark documents received**.
4. A confirmation asks you to confirm. It says this gives a student number and **cannot be undone**.
5. The student number is shown on screen.

The checklist by type:

| Document | New | Transferee | Foreign |
|---|---|---|---|
| Endorsement Slip signed by the Admissions Officer | Yes | Yes | Yes |
| PSA birth certificate (original and photocopy) | Yes | Yes | Yes |
| One recent 2x2 photo, white background | Yes | Yes | Yes |
| Printed Student Information Form | Yes | Yes | Yes |
| Two valid IDs (one showing current address) | Yes | Yes | No |
| Form 138 (report card) | Yes | No | No |
| TOR marked "Copy for PLP" | No | Yes | Yes |
| Passport | No | No | Yes |
| Visa or Study Permit | No | No | Yes |
| Alien Certificate of Registration | No | No | Yes |
| Form 137 (original SHS, marked for PLP) | Can be late | No | No |

Notes:

- You cannot mark documents received while any required item is missing. There is no way around this.
- **Form 137** may come later. The student is still promoted, and Form 137 stays open on their card until you tick it.
- If Admissions already checked a scan of a document, the checklist says **"Scan verified in Admissions"**. This is only a hint. You still tick the original yourself.
- No scans are kept in this system. The checklist only records that you received the original.

**Received tab:** students whose documents were received. You can open a student to tick a late item (like Form 137).

**Correct student details:** on a student's row. Use it to fix a misspelled name or wrong email. You must give a reason. The student signs in with the new email. Papers already printed are not changed. The student number, program and section are not touched.

**Withdraw:** see [section 8](#8-withdrawals).

**Withdrawn tab:** people who withdrew, with the date and reason.

### Schedules

Same page the Secretary and Dean use (see [section 6](#6-page-by-page-college-secretary-and-dean) for how it works). As Registrar, you:

- See sections and filter by Program and Status.
- Open a section to review its subjects, professors, rooms, times and students.
- When a section says **Waiting for Registrar**, press **Approve schedule**, or press **Reject**, type a reason and press **Send back to draft**.
- You cannot edit a section's name or capacity.

### Slips (Assessment slips)

Lists every student whose section is approved and who has no slip yet.

- Press **Issue** beside a student, or **Issue all** to do everyone on the list.
- If the program requires payment, a pending payment is created automatically for Finance.
- The slip remembers whether payment was required on the day it was issued.

### COR (Certificates of registration)

Lists students who have a slip and either paid or do not need to pay.

- Press **Issue** beside a student, or **Issue all**.
- A COR cannot be issued until the Admin has set the school year and semester. If it is missing, the system tells you to ask the Admin.
- The COR carries the school year and semester it was issued for.

### Grades

See [section 9](#9-grades). The Registrar approves grade changes here.

The page also has the **Close term** bar at the top and two read-only tabs, **Completed** and **On leave**. Closing a term is explained in [section 9](#9-grades). **On leave** lists the students who have an approved or running leave of absence, with the first term, the length and the return term.

The **Changes** tab also lists **credits** waiting for you. A credit is a subject a transferee already finished in earlier schooling. Each row shows the student, the subject, the reason (which names the line of the transferee's TOR) and who recorded it.

- **Approve** makes the credit count as a pass. It has no grade number.
- **Reject** needs a reason. The credit does not count, and the Dean or Secretary can record it again.

### Prerequisites

Open [Prerequisites](/registrar/prerequisites) to see which subjects need which earlier subjects. Choose a program to see its subjects. You can only read this page. Admin and the Dean set prerequisites.

---

## 6. Page by page: College Secretary and Dean

### Schedules (shared by Secretary and Dean)

This is where a section's schedule is prepared, signed off and approved. You only see your own college. Open it at [Schedules](/secretary/schedule).

**Top of the page**

- **New section:** choose the program, year level and capacity (seats). You do not type a name. The system gives the next letter by itself: the first section for a program, year level and term is **A**, the next is **B**, then **C**, and so on. The name shown everywhere is the program code, the year level number and the letter together, so the first section of Year 1 in BSIT is **BSIT 1A** and the next one is **BSIT 1B**. The count starts again at A for each program, each year level and each term.
- **Edit:** change a section's name or capacity. Program and year level can never change.
- Filters: Program and Status.
- **Waiting for a section:** students who are not in any section yet. Choose a section beside a name and place them.

**When you create a section**, the system fills in the subjects for that program, year level and semester by itself. Subjects with a laboratory get a second row, for example "COMP 104" and "COMP 104 Lab". Students who were waiting are placed into the new section automatically.

**Opening a section**

You see its status, how many students it has, its subjects and its students.

For every subject, set:

- Professor
- Room
- Day
- Start time and End time

Then press **Save** on that subject.

The system refuses these:

- A professor cannot be in two classes at the same time.
- A room cannot be used by two classes at the same time.
- The professor must be an active Professor account.
- A room that belongs to another college is refused.

**The approval chain**

| Status | Meaning | Who acts |
|---|---|---|
| Draft | Being prepared | Secretary or Dean: **Submit for sign-off** |
| Waiting for Dean | Waiting for professor loading sign-off | Dean: **Sign off professor loading** or **Reject** |
| Waiting for Registrar | Dean signed | Registrar: **Approve schedule** or **Reject** |
| Approved | Done. Students can get slips. | |

Rules:

- **Submit for sign-off** only works when the section has subjects and every subject has a professor, room and time. The system tells you how many are still missing.
- Once submitted, professor loading is locked.
- **Reject** needs a reason. The section goes back to Draft and the Secretary sees the reason ("Sent back: ...") and fixes it.

**Moving a student to another section**

On the section's student list, choose another section beside a student. This works until that student's assessment slip is issued. It must be a section of the same program and college. It may go over capacity.

**Changing an approved schedule**

After approval, the Secretary, Dean or Admin can still change a subject's professor, room, day or time. You must type a reason, which is saved in the history. This is allowed until any student in the section has a COR. All students in the section are told. Their slip keeps the first schedule, and their COR shows the final one.

### Home (Secretary and Dean)

- A list of your pages with counts ("Schedules" waiting on you, and "Waiting for a section").
- **Drafts in progress** (Secretary) or **Waiting for your sign-off** (Dean).
- The pipeline of sections by status and how full your sections are.

### Grades (Dean)

Open [Grades](/dean/grades). See [section 9](#9-grades).

### Prerequisites (Dean sets, Secretary reads)

A prerequisite is an earlier subject that a student must have **passed** before taking a later one. Open [Prerequisites](/dean/prerequisites) (Dean) or [Prerequisites](/secretary/prerequisites) (Secretary). You only see the programs of your own college. Setting a prerequisite does not change any schedule that already exists. The system uses it when it checks whether a returning student may take a subject.

1. Choose the **Program**. Each subject is listed with its year level, semester and the subjects it requires.
2. The Dean presses **Edit** on a subject. The Secretary cannot edit.
3. Choose every subject that must be passed first. **All** the chosen subjects are required. There is no "either one" rule.
4. Press **Save**. Saving replaces the whole list of that subject.

The system refuses these, and says which subject is the problem:

- A subject that requires itself.
- A subject from another program.
- A subject that is not earlier in the curriculum. An earlier subject is in a lower year level, or in the same year level and an earlier semester.
- A subject that has no year level. Its place in the curriculum is not known, so it cannot take or be given a prerequisite.

What counts as passed:

- A **Passed** grade in a subject whose grades the Dean approved. Any attempt counts, so a retake that passes unblocks the student.
- An **approved credit** (see below).
- Incomplete, Failed, Dropped, a subject never taken, and grades still waiting for the Dean do **not** count.

### Credits for a transferee

A credit marks a subject as passed because the student finished it in earlier schooling.

1. Open the student's section in [Schedules](/secretary/schedule).
2. Press **Credits** beside the student. The window shows the credits already recorded and whether each is waiting, approved or rejected.
3. Under **New credit**, choose the **Subject** and type the **Reason**. Name the line of the transferee's TOR that shows the subject.
4. Press **Record credit**.

The credit waits for the Registrar. Until the Registrar approves it, it does not count. Only the Dean, the Secretary and Admin can record a credit, and only for a student of their own college. You cannot credit a subject the student has already passed or has already been credited, or one that has a credit waiting. The student must be in a section to appear in the list.

### Building a load for a student who needs review

After a term closes, a student who did not pass everything is on the **Needs review** tab of [Schedules](/secretary/schedule), with the reason. A student coming back from a leave of absence is on the same list, with **Returns** and the term instead of **Closed**.

1. Press **Open** beside the student.
2. If the student has no section in this term, choose one under **Place** and press it first.
3. Under **Can be added**, choose a section for a subject and press **Add**. Any section of this term that offers the subject will do.
4. Under **In the load**, press **Remove** beside a subject you added by mistake. A subject copied from the student's section stays.
5. Press **Credits** at the bottom left to record a credit for a transferee (see above). It counts only after the Registrar approves it.

**Blocked** subjects name the prerequisite that is not passed, and cannot be added by anyone, Admin included. A subject that is not offered in this semester, one the student already passed, a full section, a clash in time, or a slip that was already issued also stops the add, and the window says why. The student is told when a subject is added or removed.

When a returning student is placed in a section, the leave is marked as returned, the account is switched back on and the readmission slip is issued.

### Leave of absence

A leave of absence lets an enrolled student stop for one or two regular terms and come back. Students never file it themselves: the Secretary or the Dean records it, and the Dean decides.

**Recording a leave (Secretary or Dean)**

1. Open the student's section in [Schedules](/secretary/schedule), or the student's load window, and press **Leave** beside the student.
2. Choose the **First term of the leave**. A leave starts at a 1st or 2nd semester, never before the current term, and not in a term the student is already placed in.
3. Choose the **Length**: 1 term, or 2 terms (one academic year).
4. Type the **Reason** (up to 500 characters) and press **Record leave**.

The window also lists the leaves already recorded and how many of the 4 terms of leave (two academic years in all) the student has used. Summer terms are skipped: a leave counts regular terms only.

The system refuses a leave and says why when:

- The student has no enrollment yet. A new student can withdraw instead.
- The student withdrew, or belongs to another college.
- The student already has a leave that is not finished.
- The leave would go past 4 terms in all.

**Deciding a leave (Dean)**

Open [Grades](/dean/grades), tab **Changes**. Each leave waiting for you shows the student, program, first term, length, return term, reason and how many terms are used. Press **Approve**, or **Reject** and type a reason. A rejected leave keeps the student enrolled and the person who recorded it is told. If the first term has already started, or the student is already placed in it, the leave cannot be approved. Reject it and record a new one.

**What the system does by itself**

- When the first term of an approved leave opens, the leave becomes **On leave** and the student's account is switched off.
- A student on leave is not moved up when the next term opens.
- When the return term opens, the leave becomes **Leave ended, not yet returned** and the student appears on **Needs review** with **Returns** and the term.
- The student is not placed automatically. The Secretary or Dean builds the load as described above. That marks the leave returned, switches the account back on and issues the readmission slip.

The Registrar can see everyone on leave under [Grades](/registrar/grades), tab **On leave**. It is read only.

---

## 7. Reschedules

The student never picks a new date. Staff or the system do.

### A student asks for a reschedule

1. On their **Your next step** card, the student presses **Request a reschedule**.
2. They type a reason and send it. Only one request can wait at a time.
3. The card then says the request is waiting for the Registrar.

### The Registrar answers

1. Go to [Reschedules](/registrar/reschedules), tab **Requests**, and open the request.
2. Optionally choose **Move to** a specific slot. If you leave it empty, the system uses the next open slot on a different date.
3. Add a note. The note is optional when approving and **required when declining**. The student sees it.
4. Press **Approve** or **Decline**.

If no slot with a free seat exists, the system tells you to add a slot first.

A visit already marked attended or no-show cannot be moved.

### Mass reschedule (typhoon, suspension, closure)

Registrar or Admin only.

1. Go to [Reschedules](/registrar/reschedules?tab=mass), tab **Mass reschedule**.
2. Choose the **Affected date**. It cannot be in the past.
3. Optionally narrow it by **Program** and **Office**.
4. Type the **Reason**.
5. Press **Move visits** and confirm. This cannot be undone.

The system moves every booked person on that date to the next open slot on a different date. It tells you how many were moved. If some people do not fit, they stay where they are and are counted. Add more slots and run it again.

A reschedule changes only the visit date. Nobody becomes a no-show, and documents, progress and student number stay as they are. The reason is saved in the history.

---

## 8. Withdrawals

### A student or applicant withdraws on their own

Allowed until their COR is issued.

1. Open the profile menu and press **Withdraw enrollment**.
2. Type a reason and type the word **withdraw** to confirm.

### The Registrar or Admin withdraws someone

On the [Documents](/registrar/documents) page, press **Withdraw** on the person's row. Works at any stage. Type a reason and type the person's student number (or applicant reference) to confirm.

### What happens

- The visit slot is freed.
- The section seat is freed, and the next waiting student is seated automatically.
- A payment that was still pending is removed.
- A payment already cleared stays on record. Refunds are Finance's job and are not handled here.
- The student number, slip and COR (if any) stay as history.
- The person is told on their card. If staff withdrew them, the card shows the reason.
- The person no longer appears in waiting lists, counts or the funnel.
- If Admissions sends the same person again, nothing changes. They stay withdrawn.

**This cannot be undone in the system.** To bring someone back, they must contact the Registrar.

---

## 9. Grades

### Before anything: the grading scale

The Admin must set the scale first, under [Content, Grading](/admin/content?tab=grading). Nothing is pre-filled.

- **Days an incomplete stays open:** after this many days, an incomplete that was not completed becomes a failed 5.0 by itself.
- **Bands:** each band has a Label (for example 1.00 or INC), an Outcome (Passed, Incomplete, Failed or Dropped), and From and To numbers for number grades. A band can be marked **Display only** if it should not decide any outcome.
- Two number bands cannot overlap.

The system does not guess whether a high or low number is better. The bands you set decide it.

### Professor: entering grades

1. Go to [Grades](/professor/grades), tab **Subjects**. You see only your own subjects.
2. Open a subject. Every student is listed.
3. Type a grade for each student. It must match the scale (a number inside a band, or a label like INC).
4. Press **Save** to keep a draft, or **Submit to Dean**. Every student needs a grade before you can submit.

After submitting, you cannot edit unless the Dean returns it.

### Dean: approving grades

Open a submitted subject and press **Approve**, or **Return** with a reason. A returned sheet shows the reason to the Professor. An approved sheet is locked.

### Changing an approved grade

1. The Professor opens the subject and presses **Propose change** next to the student, types the new grade and a reason.
2. The Dean opens **Grades**, tab **Changes**, and presses **Sign** (or **Reject** with a reason).
3. The Registrar then presses **Approve** (or **Reject** with a reason).

The type of change is shown: Correction, Completing an incomplete, or Official drop. Only one change can wait for the same grade at a time. The grade only changes after the Registrar approves.

### Incomplete grades that run out

When the Dean or Registrar opens their Grades page, the system checks for approved incompletes that are past the allowed days and turns them into a failed 5.0. A grade that has a change waiting for a signature is left alone.

### Closing a term (Registrar or Admin)

Open [Grades](/registrar/grades). The **Close term** bar at the top names the current term and how many students are enrolled. The button stays off, and the bar names the subjects, until every section subject that has students has Dean-approved grades. If no term is set, ask the Admin to set it.

1. Press **Close term**.
2. Read the confirmation and press **Close term** again. **This cannot be undone.**

Closing decides, for every student enrolled in that term:

- **Promote:** every subject of the section was passed. The student moves up when the next term opens.
- **Review:** anything else, such as an incomplete, failed or dropped subject. The reason is written in words and the student goes to the **Needs review** list of their college.
- **Completed:** passed the last semester of the last year of the program. They appear on the **Completed** tab. Graduation itself is not handled in this system.

A student who withdrew, or who has no enrollment in the term, gets no result. Closing a summer term only records the closure and decides nothing for anyone.

### Opening the next term (Admin)

The Admin changes the school year and semester in [Content, Term](/admin/content?tab=term). If the term before it was closed, changing the term opens the new one by itself:

- The new term's sections are made by copying the closed term's: same names and capacities, with the subjects filled in from the subject list. They have **no professors, rooms or times**. The Secretary prepares them and sends them for sign-off as in [section 6](#6-page-by-page-college-secretary-and-dean). When a new school year starts, sections move up one year level.
- Every student marked **Promote** is seated in the right section if a seat is free, and is told. A student who cannot be seated goes to **Needs review** with the reason. A student on an approved leave is not seated.
- Terms go 1st semester, 2nd semester, then 1st semester of the next school year. Summer is never part of the automatic move up.

Close the old term first. If it was not closed, changing the term only changes the term.

---

## 10. Page by page: Finance

Sidebar: [Home](/finance), [Payments](/finance/payments).

### Home

How many payments are waiting, how much has been collected in total, the next students in line, and the latest cleared payments.

### Payments

Three tabs.

**Pending:** students whose slip was issued and who must pay.

1. Open a student.
2. Type the **Amount due**.
3. Type the **Amount paid**. It must cover the amount due. Part payments are not accepted.
4. Type the **Receipt number**.
5. Save. The payment is cleared and the student is told.

**Cleared:** payments already recorded.

**Programs:** one switch per program called **Payment required**.

- Switch it on or off. Finance and Admin can change it. The Registrar and Dean can only see it.
- A change only applies to slips issued from then on. Slips already issued keep the setting they had.
- When it is off, no payment step exists for that program. The student goes straight from slip to COR.

---

## 11. Page by page: Professor

Sidebar: [Home](/professor), [Grades](/professor/grades).

### Home

- Today's date and your **next class** (or the class happening now).
- Your subjects in approved schedules, with section, day, time and room.
- A class list for each subject, showing only student name and student number.

### Grades

See [section 9](#9-grades).

---

## 12. Page by page: Admin

Sidebar: [Home](/admin), [Accounts](/admin/accounts), [Content](/admin/content), [Prerequisites](/admin/prerequisites), [Admissions](/admin/admissions), [Audit log](/admin/audit), plus every other staff area (Registrar, Finance, Dean, College Secretary, Professor). Admin can open and do everything those roles can.

### Home

The list of all pages with waiting counts, the funnel, visit capacity, the schedule pipeline, and the latest changes made in the system. The current school year and semester are shown at the top. If no term is set, a warning appears with a link to set it.

### Accounts

Create staff accounts.

1. Type the **Full name** and **Email**.
2. Choose the **Role**: Registrar, Finance, Dean, College Secretary or Professor.
3. For Dean and College Secretary, also choose the **College**.
4. Press **Create account**.

The person gets an email to set their own password. You never see or choose a password. Each person must have their own account, not a shared one.

Applicants and students are not created here. They arrive from Admissions.

### Content

Four tabs.

**Subjects:** choose a program, then **Add subject** with Code, Title, Units, Year level, Semester, whether it has a laboratory, and whether it is also offered in summer. You can edit a subject. You cannot delete a subject that is already in a section, or that has a grade or a credit. You also cannot delete a subject that other subjects require. The message names those subjects. Remove it from their prerequisites first, then delete it. New subjects are added to existing draft sections of the matching year level and semester automatically.

**Rooms:** **Add room** with Name, Capacity and College. A room used by a section cannot be deleted.

**Term:** set the **School year** (like 2026-2027) and the **Semester** (1st, 2nd or summer). Nothing can be built without this. A section cannot be created and a COR cannot be issued until a term is set. Change it when a new semester starts. Changing it also opens the new term: it makes the new sections and moves up the students who passed (see [section 9](#9-grades)). Close the old term first.

**Grading:** the grading scale (see [section 9](#9-grades)).

The 7 colleges and 13 programs are already loaded. Program codes match Admissions on purpose, so they are not editable.

### Prerequisites

Open [Prerequisites](/admin/prerequisites). Admin can set the prerequisites of every program. The page works the same way as the Dean's page, described in [section 6](#6-page-by-page-college-secretary-and-dean). A subject with no year level cannot take or be given a prerequisite, because its place in the curriculum is not known.

### Admissions

Shows what Admissions has sent.

- **Accept requests from Admissions** switch: turn the connection on or off.
- A table of every request: when it came, reference, name, program, status (Accepted or Rejected) and the reason if rejected.
- **Resend** on a rejected request tries it again. Use it after fixing the cause (for example switching the connection back on).

Common reasons for rejection: the program code is not recognized, or the email already belongs to another account.

### Audit log

A read-only history of every important change: who did it, what, and when.

- Filter by **Table** (Visit slots, Payments, Students, and so on) and by **Action** (Created, Changed, Deleted).
- 50 rows per page, newest first.
- Press **Details** to see each field's value before and after, and the reason if one was given.

Admin actions are logged like everyone else's.

---

## 13. What the system does by itself

The system does these without anyone doing anything. The section number shows where each one is explained.

- Creates the applicant account, sends the set-password email and books the first visit ([section 3](#3-the-whole-journey-from-start-to-end) and [section 5](#5-page-by-page-registrar)).
- Gives the student number and places the student in a section when documents are received ([section 3](#3-the-whole-journey-from-start-to-end) and [section 6](#6-page-by-page-college-secretary-and-dean)).
- Fills new sections with subjects, blocks double booked professors and rooms, and tells students when their schedule is approved or changed ([section 6](#6-page-by-page-college-secretary-and-dean)).
- Opens a pending payment only when the course requires payment, and skips Finance when it does not ([section 10](#10-page-by-page-finance)).
- Moves everyone in a mass reschedule ([section 7](#7-reschedules)).
- Frees the visit slot and seat when someone withdraws, and seats the next waiting student ([section 8](#8-withdrawals)).
- Turns an unfinished incomplete into a failed 5.0 when the allowed days pass ([section 9](#9-grades)).
- Decides promote, review or completed for every student when the Registrar closes a term, and moves the promoted students into the new term's sections when the Admin opens it ([section 9](#9-grades)).
- Starts and ends leaves of absence, switching the student's account off and on again ([section 6](#6-page-by-page-college-secretary-and-dean)).
- Keeps the **Your next step** card up to date for every student ([section 3](#3-the-whole-journey-from-start-to-end)).
- Tells Admissions when a student gets a number and when they are enrolled. If Admissions is down, it tries again later and catches up when you open the Documents or COR page.
- Writes every important change to the audit log ([section 12](#12-page-by-page-admin)).

---

## 14. Before the first day: setup checklist (Admin)

Do these in order.

1. Create the staff accounts in [Accounts](/admin/accounts) (Registrar, Finance, Dean and Secretary for each college, Professors).
2. In [Content, Term](/admin/content?tab=term), set the school year and semester. Sections and CORs cannot be made without it.
3. In [Content, Subjects](/admin/content?tab=subjects), add the subjects for every program, year level and semester.
4. In [Content, Rooms](/admin/content?tab=rooms), add the rooms.
5. In [Content, Grading](/admin/content?tab=grading), set the grading scale.
6. In [Finance, Payments, Programs](/finance/payments?tab=programs), check which programs require payment.
7. In [Admissions](/admin/admissions), check that the connection switch is on.
8. Registrar: create visit slots in [Visits](/registrar/visits) for each program before applicants arrive.
9. Secretary or Dean: create the sections in [Schedules](/secretary/schedule) for each program so new students can be placed.

---

## 15. When something looks wrong

| What you see | What to do |
|---|---|
| An applicant says "Waiting for your visit schedule" | No slot was free. Registrar adds a slot on [Visits](/registrar/visits), then presses **Assign all unassigned**. |
| A student is not in any section | There is no section or no free seat for their program. Create a section or raise capacity. They are placed automatically once a seat opens, or move them by hand. |
| A new section shows no subjects | The Admin has not added subjects for that program, year level and semester. In the section, the Admin sees an **Add subjects** link to [Content](/admin/content); everyone else is told to ask an Admin. |
| A student cannot get a slip | Their section schedule is not approved yet. |
| A student cannot get a COR | The slip is not issued, or payment is not cleared yet. |
| A request from Admissions is Rejected | Open [Admissions](/admin/admissions), read the reason, fix it, then press **Resend**. |
| A student cannot sign in | Check they use the email on their account. If it was wrong, correct it on the [Documents](/registrar/documents) page. If their link expired, ask the Admin for a new one. |
| A subject cannot be deleted | Another subject requires it, or it is in a section, or it has a grade or a credit. The message names the subjects that require it. Open [Prerequisites](/admin/prerequisites), remove it from their lists, then try again. |
| The **Close term** button is off | The bar names the subjects whose grades the Dean has not approved. Follow up with the Dean, then try again. |
| A student who passed is not in a section of the new term | There was no free seat or no matching section. The student is on **Needs review** with the reason. Create a section or raise capacity, then place the student. |
| A returning student cannot be placed: "on leave of absence until..." | The leave has not reached its return term yet. The student can be placed once the return term opens. |
| A leave cannot be recorded | The message says why: no enrollment yet, a leave already open, more than 4 terms in all, or a start that is too early. |
| A student on leave cannot sign in | Expected. The account is switched off during the leave and back on when the student is placed in a section after the return term opens. |
| A person withdrew by mistake | It cannot be undone in the system. The person must contact the Registrar. |
| A slot cannot be cancelled | Someone is booked in it. Move them first, or close the slot instead. |

For any other error message, read it. It says what is missing.

### About emails

At the moment, the system sends emails only for account setup (the set-password link). Updates about visit dates, reschedules and the other steps are shown on the student's **Your next step** card. Please tell students to check their card after signing in.

### Who to ask

For anything not covered here, contact the Admin.
`;
