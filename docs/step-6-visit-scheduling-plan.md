# Plan: Step 6, Visit scheduling (plp-enrollment)

Status: **closed, ready to build.** Nothing is built. Written against the Enrollment repo as uploaded on 2026-10-25, after the Admissions sender drop. Admissions code was checked on the same day (section 8).

## 1. Goal

The Registrar sets up visit slots per program. The system puts each new applicant into a slot. The applicant never picks one. They see where and when to go on their persistent "Your next step" card.

Env vars and the email sender are a separate session. This step writes the notification rows and leaves their email `pending`.

## 2. Decisions (all closed)

| # | Question | Decision |
|---|---|---|
| A | Who assigns applicants? | The Registrar (or Admin) picks a program and presses **Assign all unassigned**. The system fills the earliest open slots in order. The Registrar can also assign or move one applicant by hand. No silent auto-assign on intake, because applicants often arrive before any slots exist. |
| B | Email half of notifications | Build the card and write `notifications` rows now, with `email_status` left as `pending`. The sender comes with the env vars session and picks up the pending rows. |
| C | How do notifications get written? | **Database functions** (security definer, Registrar and Admin only) that make the booking and the notification in one transaction. Same pattern as the student number. Server actions with the service role would split the two writes. |
| D | "What to bring" source | New nullable `visit_slots.what_to_bring` text, **required by the slot form**. The form is pre-filled with PLP's published list (below) so the Registrar edits rather than types. The system never invents requirements. Per admission type lists (including `foreign`, decision #13) come in step 7. |
| E | A slot with bookings | Can be **closed** (no new bookings) but not **cancelled**. Moving people off a cancelled slot is the mass reschedule in step 12. Capacity cannot be lowered below the number already booked. |
| F | Attended and no show | Step 6 sets neither. Step 7 sets `attended` when the Registrar marks documents received. `no_show` stays unset until a later decision. |
| G | Admissions gate `enrollment_schedule_posted()` | Dropped **after** the Enrollment visit page is live, in the cleanup commit (section 8). Until then it stays unchanged. |
| H | Endorsement Slip | The last Admissions page for an accepted student becomes an Endorsement Slip: name, program, application number, and "Proceed to the Enrollment portal for your visit date". It carries **no date**. "Endorsed" in Enrollment means the admission record was received. |

### Seed text for "what to bring" (from PLP's published AY 2026-2027 notice)

Originals and photocopies of:

1. Form 138 (new students), or a TOR marked "Copy for PLP" (transferees and Balik Aral).
2. Birth certificate on PSA paper.
3. One recent 2x2 photo, white background.
4. Two valid IDs with photocopies, at least one showing the current address.
5. Printed Student Information Form.
6. Original SHS Form 137 marked "Copy for Pamantasan ng Lungsod ng Pasig".
7. Endorsement Slip from Admissions.

Source: plpasig.edu.ph notice "Congratulations to our successful PLP applicants" (2026-05-15). The Registrar should confirm the list each cycle, since it changes. Transferee and Balik Aral variants are step 7.

> Changed in step 7 (decision-log.md #17): the slot's "what to bring" field is now optional extra notes with no pre-filled text. The list the applicant sees comes from the document catalog for their admission type, with the slot notes added after it. Decision D and the seed text above describe step 6 as built; the seed text now lives in the catalog.

## 3. What exists today

- Tables `visit_slots` and `visit_bookings` (init migration, section 5). One booking per applicant (`applicant_id` unique), so moving someone changes `slot_id`.
- Trigger `enforce_booking_capacity`: locks the slot row, rejects a slot that is not open, a slot for a different program, and a full slot.
- Audit triggers on both tables, so every slot and booking change is logged with the actor.
- Policies: `registrar` and `admin` write slots and bookings. An applicant reads only their own booking and slot. Dean, College Secretary and Finance see no slots.
- `notifications` already has everything the card needs: `kind`, `title`, `message`, `office_name`, `window_label`, `scheduled_for`, `what_to_bring`, `email_status`. Only the owner can read it, and only Admin can write it directly.
- The portal shell shows a static "Nothing to do yet" in `data-slot="next-step-card"`. `features/visit-scheduling/` and `features/next-step-card/` exist as empty folders. `/registrar` and `/applicant` are placeholders.
- Registrar and Admin can both open `/registrar/*` (`lib/auth/roles.ts`).
- "Unassigned" has no flag. It means an applicant with no `visit_bookings` row.

## 4. Design

### Database (one forward-only migration, `20261025040000_visit_scheduling.sql`)

1. `visit_slots.what_to_bring text NULL`.
2. A guard trigger on `visit_slots`: capacity cannot drop below the current bookings, a slot with bookings cannot become `cancelled`, and its program, date, time and office cannot change (a silent change would move applicants without telling them; moving people is a reschedule). `what_to_bring` and status stay editable.
3. `next_open_slot(p_program uuid)`: the earliest open slot of that program, from today (Manila time), with free capacity. Built once here, reused by the mass reschedule in step 12.
4. `assign_visit_slot(p_applicant uuid, p_slot uuid, p_reason text default null)`: creates the booking, or moves an existing one, and writes the `notifications` row (`visit_assigned` or `visit_moved`) in the same transaction. The optional reason goes into the audit log through `app.audit_reason`.
5. `assign_unassigned_visits(p_program uuid)`: applicants of that program with no booking, in order of `admission_date` then `created_at`, each placed with `next_open_slot`. Returns how many were assigned and how many are left because slots ran out.
6. All three check `app_role() IN ('registrar','admin')` themselves, and execute is revoked from `public` and `anon`.

Times are `date` and `time` in Manila time. `notifications.scheduled_for` is built as Manila time, and `window_label` reads like "9:00 AM to 12:00 PM".

### Registrar pages and actions

- `app/(portal)/registrar/visits/page.tsx`: slot list with filters (program, date), create and edit form, close and cancel buttons, and per slot the booked applicants.
- Unassigned panel: applicants with no visit, per program, with **Assign all unassigned** and a per applicant "Assign to slot" picker. A booked applicant has a "Move to slot" picker with an optional reason.
- Files follow the feature folder rule: `features/visit-scheduling/` holds `schema.ts` (input checks), `queries.ts`, `actions.ts` and the form and list components.
- Slot rules in `schema.ts`: date not in the past, end after start, capacity above 0, office name and "what to bring" required. The "what to bring" field is pre-filled with the seed text above.
- Reached from a link on the Registrar home and the Admin home (the shell has no nav yet).
- All reads and writes use the signed-in session (`lib/supabase/server.ts`), per decision #10.

### "Your next step" card

- `features/next-step-card/` holds the data function and the card component. The portal layout loads it and hands it to the shell, so it appears on every page.
- The applicant card is computed from the live booking, not from the latest notification, so it can never be stale after a move.
  - No booking: "Waiting for your visit schedule. The Registrar will assign a date and you will see it here."
  - Booked: date, time window, office, and what to bring.
- Other roles keep "Nothing to do yet" until the dashboards in step 14.
- No reschedule button yet. The card leaves room for it (step 12).

## 5. Build order

Each step ends in something that can be checked. Read `docs/ux-ui-guidelines.md` and `scripts/design-gate.mjs` before step 4, so the pages pass the design gate.

1. **Migration** `20261025040000_visit_scheduling.sql` (section 4).
2. **Database checks** added to `supabase/gates_check.sql` (section 6).
3. **Feature code**: `schema.ts`, `queries.ts`, `actions.ts`.
4. **Registrar page** and the links from the Registrar and Admin homes.
5. **Next step card** wired through the layout and shell.
6. **Docs**: build step 6 ticked in `build-order.md`, and a decision-log entry only if something here proves hard to reverse. Record decisions F, G and H in the log, since G and H change Admissions.
7. **Admissions cleanup** (section 8), as its own later commit, only after steps 1 to 5 work live.

## 6. Acceptance checks

- A slot cannot be created in the past, with a bad time window, or with zero capacity.
- A full, closed or cancelled slot rejects a booking, and a slot for another program rejects it.
- Two Registrars assigning into the last seat at once: one succeeds, the other gets "slot is full" and no half written notification.
- **Assign all unassigned** orders by admission date, fills earliest slots first, and reports the number left without a slot.
- Capacity cannot be lowered below the booked count. A slot with bookings can be closed but not cancelled.
- An Applicant, Student, Finance, Dean or College Secretary calling the functions directly is refused. Admin and Registrar succeed.
- Every assignment and move writes a `notifications` row with `email_status = 'pending'` and one audit row per table change, with the actor.
- The applicant sees only their own visit. A different applicant's slot returns nothing.
- Moving an applicant changes `slot_id` only: no new booking row, student number and documents untouched.
- The slot form opens with the seed "what to bring" text and refuses an empty value.
- The page and card pass lint, type check, and the design gate in CI.

## 7. Risks and open items

- If the program has fewer slots than applicants, the rest stay unassigned and the Registrar must add slots and press the button again. The page shows that count so it is not silent.
- Pending emails pile up until the sender exists. Nothing is lost, but applicants only see the card, not an email, in the meantime.
- Two Registrars pressing **Assign all unassigned** together can make one call fail on the capacity trigger. A retry fixes it.
- PLP's real process lets applicants reserve a slot through an Enrollment Link and serves first come, first served. This plan replaces that with Registrar assignment (decision #14). Tell the Registrar's office before go-live, since it changes what applicants have been told.
- The seed "what to bring" list is taken from a public notice and can go out of date. The Registrar owns it each cycle.
- Carried to step 7: no-show handling (decision F), whether the Registrar needs a visible "endorsed" marker (decision H), and Transferee, Balik Aral and `foreign` lists.

## 8. Admissions cleanup (decisions #14, G and H)

Checked against the Admissions code. Admissions has one global schedule (date, time, venue) in School Year settings. It has no per-program dates, no reservation link and no endorsement slip. The `enrollment_schedule_posted()` gate in `core/helpers.php` only exists so an accepted student never sees "schedule not posted yet". No data depends on it.

After this step works live in Enrollment, do one small Admissions commit so students see one date:

- Replace the "Enrollment Schedule" block in `modules/results/student_view.php` with the **Endorsement Slip** (name, program, application number, "Proceed to the Enrollment portal for your visit date"). No date on it. Generate it from the accepted result. Optionally print the releasing officer's name from the release record.
- Keep the existing "documents to bring" block, which already lists the applicant's uploaded documents.
- Drop the `enrollment_schedule_posted()` gate and its callers: `staff_action.php` (override to Accept), `staff_bulk.php` (`bulk_accept`, `release_selected`), `staff_manage.php` (the warning banner) and the function in `core/helpers.php`.
- Remove the `set_enrollment_schedule` action and the Enrollment Schedule card from `modules/settings/admin_school_year.php`. Old `enrollment_*` settings rows can stay.

Do not do this before the Enrollment page is live, or students will have no date anywhere.

## 9. Not in this step

- Student reschedule requests and mass reschedule (step 12).
- Marking attended or no show (step 7 for `attended`).
- Sending the emails (env vars session).
- Per admission type "what to bring" lists (step 7).
- Assessment slip and COR (later Enrollment steps).
- Role dashboards beyond the card (step 14).
