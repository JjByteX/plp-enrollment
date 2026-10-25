# Plan: Step 16, Schedule changes after the assessment slip (plp-enrollment)

Status: **plan only, nothing built.** Decisions A, B and C are settled below (the recommended option was taken for each). Written against the Enrollment repo as uploaded on 2026-10-25.

## 1. Goal

The assessment slip keeps the schedule as it was first issued. The schedule can then change, and the COR shows the final schedule. This is how PLP has always worked: the slip is the first schedule, the COR is the finalized one.

This serves the project goal (finalized enrollment, the COR) and does not add a new role, page or sidebar item.

## 2. What exists today

- **The slip and the COR read the live schedule.** `assessment_slip()` (latest version in `20261025090000_laboratory_meetings.sql`) joins `section_subjects` at read time. `certificate_of_registration()` (`20261025110000_cor.sql`) calls `assessment_slip(p_student)->'subjects'`. Neither stores the schedule when it is issued. `assessment_slips` holds only `payment_required`, `issued_by` and `issued_at`. `cors` holds only the term, `issued_by` and `issued_at`.
- **An approved schedule cannot be changed.** `enforce_section_subject_rules()` (`20261025070000_section_scheduling.sql`, section 3) refuses any insert, update or delete on `section_subjects` unless the section is `draft`. Decision #18: an approved schedule cannot be rejected.
- **Student moves are locked after the slip.** `move_student_section()` refuses once an assessment slip exists (decision #19). This plan leaves that as it is.
- **The COR already keeps its own term** (decision #21), so an old COR never changes when the term changes. It does not keep its own schedule.
- **Consequence.** If a schedule did change (for example by SQL), the slip would change with it, so the slip would no longer show the first schedule.
- **The UI.** `SectionDetailsModal.tsx` sets `canEditLoading = isCollege && status === 'draft'`. The rejection flow already has a required reason box. `actions.ts` already has `saveLoading`, `parseLoadingInput`, `parseReason` and a `failure()` that shows the database's own messages and the room or professor clash message. The student's next step card (`features/next-step-card/`) already shows the slip and COR links.

## 3. Decisions

| # | Question | Options | Status |
|---|---|---|---|
| A | Who changes an approved schedule, and does it need sign-off again? | **The College Secretary or the Dean of that college (and Admin) changes it directly, with a required reason.** Audit-logged, students told, no re-approval. Not chosen: every change going through Secretary, Dean and Registrar again (needs a change-request table and more UI), and Registrar-only changes. | Settled, recommendation taken |
| B | What kind of change? | **Section-level.** Professor, room, day or time of a subject, for everyone in the section. Not in this step: per-student add and drop of subjects. That needs a per-student subject list and probably an adjustment number. The sample PLP COR has an "Adjustment No." and an added-subject legend, so it likely exists in real life, and it is a larger step of its own. | Settled, recommendation taken |
| C | Until when can a section's schedule change? | **Until the first COR is issued for a student in that section.** After that the database refuses. This avoids a section where some CORs are out of date. Not chosen: changing any time, which would need a COR re-issue flow (a later step). | Settled, recommendation taken |
| D | How the slip and COR keep their schedule | Each stores the schedule as it was when it was issued (a snapshot column on `assessment_slips` and on `cors`). The slip function and the COR function read the stored copy. An issued slip and an issued COR never change. Same idea as decision #21. | Proposal |
| E | Slips and CORs that already exist | Backfilled from the live schedule in the migration. If a schedule was already edited by SQL, the original cannot be recovered. | Proposal |
| F | Telling students | Automatic. `amend_schedule` writes one notification per placed student (kind `schedule_changed`, email `pending`, like every earlier step). The next step card shows one line until their COR exists. | Proposal, follows the project brief (students are notified whenever their schedule changes) |
| G | Does the Registrar get a new screen or marker? | **No.** The COR picks up the final schedule by itself when it is issued, so there is no decision for the Registrar. A "changed" marker would not lead to an action (ux-ui-guidelines.md: remove it). | Proposal |

### Decisions this touches (flagged, not overridden)

- **#4** (three gates, the Dean signs off professor loading): decision A lets the Secretary or Dean change loading after approval without a new sign-off. This is a deliberate exception to the three gates for changes after approval only. The gates still apply to the first approval.
- **#18** (an approved schedule cannot be rejected): unchanged. A change is not a rejection.
- **#19** (a student cannot be moved after the slip): unchanged.
- **#21** (a COR keeps what it showed when issued): kept, and extended to the schedule.
- The comment on the trigger in the init migration ("professor loading is locked") becomes wrong for approved sections and is updated in the new function.

Two new decision-log entries are needed with this step: one for the saved copies on the slip and COR, one for the change after approval.

## 4. Design

### Database (one forward-only migration, for example `20261025180000_schedule_changes.sql`)

No merged migration is edited. Functions are replaced with `CREATE OR REPLACE`, written from the latest version, as earlier steps did.

1. **One schedule builder.** A helper function returns the schedule of one student as JSON (section label and subjects with meeting, units counted once, professor, room, day, start and end). It is built exactly as the current `assessment_slip()` builds it, so there is one definition of how a schedule is written.
2. **Slip snapshot.** Add `assessment_slips.schedule jsonb`. `enforce_slip_gate()` (init migration, replaced) fills it on insert, next to `payment_required`. `assessment_slip()` is replaced to read the stored copy instead of joining `section_subjects`.
3. **COR snapshot.** Add `cors.schedule jsonb`. `enforce_cor_gate()` (`20261025110000_cor.sql`, replaced) fills it on insert from the live schedule at that moment, which is the final schedule. `certificate_of_registration()` is replaced to read `c.schedule` instead of calling `assessment_slip()`.
4. **Backfill.** Existing rows are filled from live data, then the columns are set `NOT NULL`.
5. **`amend_schedule(p_section_subject uuid, p_professor uuid, p_room uuid, p_day smallint, p_start time, p_end time, p_reason text)`.** Security definer, same style as `move_student_section`.
   - Role and college check (Secretary or Dean of the section's college, or Admin, per decision A).
   - The section must be `approved`. A draft section keeps using the normal editing path.
   - A reason is required.
   - Refused when a student in the section already has a COR (per decision C), with a message written for the staff member.
   - Sets a transaction-local flag (like `app.audit_reason`) so the trigger allows the change.
   - Updates only professor, room, day and time. The existing clash constraints, the active-professor check and the room-college check still apply.
   - Writes one notification per student placed in the section.
   - The reason is recorded in the audit log through the existing `log_audit` path.
6. **`enforce_section_subject_rules()` replaced.** Still locked for submitted and approved sections, except an update of the five loading columns on an approved section while the flag is on. Inserts and deletes stay locked.
7. **`my_schedule_changed()`.** Returns true when the signed-in student's slip schedule differs from the current schedule and they have no COR yet. Same pattern as `my_payment_status`, because a student cannot read subjects, rooms or professors directly.
8. **Grants.** `20261025170000_grant_function_access.sql` grants `EXECUTE` to `authenticated` from a fixed list of function names, so it does not cover new functions. The new migration revokes `EXECUTE` from PUBLIC and anon, then grants it to `authenticated` for `amend_schedule` and `my_schedule_changed` itself. The schedule builder helper is internal and is not granted. Without this the app's calls fail, which is the bug that migration fixed.

### Server code

- `features/section-scheduling/actions.ts`: a new `amendLoading` action. It checks the role, reuses `parseLoadingInput` and `parseReason`, calls the new function, reuses `failure()`, and refreshes the same pages as the other actions.
- `features/next-step-card/queries.ts`: the student step gets a `scheduleChanged` flag from `my_schedule_changed()`.
- `features/audit-log/schema.ts`: no change. `section_subjects` is already in the list.

### UI (ux-ui-guidelines.md)

**Flow type:** the existing multi-section staff app and the student's linear flow. No new page, no sidebar change, no new navigation pattern.

**Automation first.** Snapshots, student notices and the COR picking up the final schedule all happen without a control. The only human decision is making the change, so there is exactly one control.

**Section modal** (`SectionDetailsModal.tsx`, the existing centered modal, which fits one viewport):
- For an approved section, allowed roles get the same row editors that a draft has (professor, room, day, start, end) and the same reason box the rejection flow uses.
- One primary action, **Change schedule**, bottom right (where the existing primary actions are).
- States:
  - Default.
  - Loading (the button's loading state).
  - Success (the existing `role="status"` line).
  - Error with the database's own message, including the room or professor clash message and the "a COR was already issued" message.
  - Disabled until a row changed and a reason is entered, with the missing item named.
- Section statuses that are not approved behave exactly as today.

**Student next step card** (`NextStepCard.tsx`): one plain line under the slip block while a COR does not exist and the schedule changed: "Your schedule changed after your slip was issued. Your COR will show the final schedule." No exclamation mark, no restating the same message twice. Once the COR exists the line is gone, because the card already says the student is officially enrolled.

**Not changed:** the slip page, the COR page, the Registrar's slips and COR queues, the dashboards. The slip page already shows its issue date, which marks it as the document as issued.

**Not used:** no new icon, no pill, no card, no table. Tokens only, so the design gate passes. Before the modal is built, the guidelines require 2 to 3 reference examples (registrar or student-portal schedule adjustment screens) to be searched and shown to you. That has not been done, because this is a plan.

**Responsive:** the modal's rows already stack. Check the new editors and the disabled-reason text at the narrow width.

### Checks (`supabase/gates_check.sql`)

Cases to add, run by you against a database:
- The slip still shows the first schedule after a change.
- A COR issued after the change shows the new schedule.
- A change in a section where a student already has a COR is refused with a clear message. The COR is untouched.
- `amend_schedule` is refused for: a draft section, another college, a missing reason, a room or professor clash, a non-professor user, and a role that is not allowed.
- One notification per placed student.
- `my_schedule_changed()` is true after a change and false once the COR exists.
- Existing step 8, 9 and 11 checks still pass, because the slip and COR functions changed.

## 5. Acceptance criteria

- An issued assessment slip never changes after the schedule changes.
- A COR shows the schedule at the moment it was issued, and an issued COR never changes.
- An approved section's loading can be changed only through `amend_schedule`, by the Secretary or Dean of that college (or Admin), with a reason, and never once a student in that section has a COR.
- Clash rules still refuse a change that puts a room or professor in two places.
- Every change is in the audit log with who, what, when and why.
- Each placed student gets a notification, and the card shows the line until their COR exists.
- Existing slips and CORs still open after the migration.
- The pages pass lint, type check and the design gate in CI, and the migration passes `supabase db reset` and `db lint` in CI.

## 6. Risks and open items

- **Backfill.** A slip that already differs from the schedule it was issued with cannot be restored. The backfill saves whatever the schedule is on the day of the migration.
- **Decision A weakens decision #4** for changes after approval. If PLP expects the Dean to sign off every professor change, this needs revisiting with a change-request flow.
- **Decision C can block a late student.** A student who pays late gets their COR after section-mates, so the section may already be locked. Tell me if that is a problem in practice.
- **Per-student changes** (decision B) are not covered and are the likely next request.
- **Professor home** reads the live schedule of approved sections, so a change shows there at once. That is the intended behavior.
- The `section_subjects` clash constraints use `slot_range`, so a change that creates a clash is refused by the database, not by the screen.
- Pending emails pile up until the sender session, like every earlier step.

## 7. Not in this step

- Per-student add and drop of subjects and an adjustment number (decision B).
- Re-issuing a COR after it was issued.
- A change-request and sign-off flow for changes after approval (decision A).
- Letting a student be moved to another section after the slip (decision #19).
- Sending the emails.
- Any new Registrar screen or marker.
