# build-order.md

What to build, in order. Each step assumes the ones before it exist. Tick a step only when it works.

- [x] 1. **CI/CD and project scaffold files**
      GitHub Actions workflow, lint, design gate, Sonar config, Supabase config, tokens, theme, fonts. See `docs/ci-cd.md`. The Next.js scaffold (`tsconfig.json`, `next.config`) is still missing.

- [x] 2. **Next.js scaffold**
      `tsconfig.json`, `next.config`, root layout, Mantine provider, folder structure from `architecture-notes.md`. Makes type check and build pass in CI.

- [x] 3. **Database schema and RLS**
      `supabase/migrations/20261025000000_init.sql` written. Gates and row level security checked on a local Postgres 16 with `supabase/gates_check.sql`; not yet run through the Supabase CLI. Follow-up migration `20261025020000_...` adds the YY-NNNNN student number, seeds the 7 colleges and 13 programs, and lets Applicants request a reschedule. Schema first, no UI yet.

- [x] 4. **Auth and roles**
      Supabase Auth, staff accounts created by Admin only, set-password link for Applicants. Decide how server code identifies the user to the database (see open-questions.md).

- [x] 5. **Admissions intake**
      `app/api/admissions/intake/route.ts`: shared secret check, program code check, create or refresh Applicant, log every request. Admin page: view requests, resend a failed one, switch the connection on or off.

- [x] 6. **Visit scheduling**
      Registrar sets up slots (date, time window, capacity per program) and assigns applicants. "Your next step" card slot in the portal shell.
      Written, not yet run: migration `20261025040000_visit_scheduling.sql`, checks in `supabase/gates_check.sql`, `features/visit-scheduling/`, `/registrar/visits`, `features/next-step-card/`. Tick this step after `gates_check.sql`, lint, type check and the design gate pass. Plan: `docs/step-6-visit-scheduling-plan.md`.
      When this ships, retire the "Enrollment Schedule" in PLP Admissions (`/admin/school-year`): replace it on the student result page with an Endorsement Slip (no date) and drop its release gate, so students see one date only (decision-log.md #14 and #15).

- [x] 7. **Documents and student numbering**
      Registrar ticks off each original document on a checklist, then marks documents received. Student number assigned automatically, Applicant becomes Student. No scans are kept (decision-log.md #16).
      Written, not yet run: migrations `20261025050000_documents_and_numbering.sql` and `20261025060000_my_open_late_items.sql`, checks in `supabase/gates_check.sql`, `features/documents-and-numbering/`, `/registrar/documents`, the student case in `features/next-step-card/`, and the optional slot notes in `features/visit-scheduling/`. Tick this step after `gates_check.sql`, lint, type check and the design gate pass. Plan: `docs/step-7-documents-and-numbering-plan.md`.

- [x] 8. **Section, professor and room scheduling**
      Secretary prepares, Dean signs off professor loading, Registrar approves. Students placed in sections. A rejection goes back to draft with a reason (decision-log.md #18); placement is automatic and movable (decision-log.md #19).
      Written, not yet run: migration `20261025070000_section_scheduling.sql`, checks in `supabase/gates_check.sql` (two older fixture lines were adjusted for the new capacity column and automatic placement), `features/section-scheduling/`, `/secretary/schedule`, `/registrar/schedules`, the student case in `features/next-step-card/`. Tick this step after `gates_check.sql`, lint, type check and the design gate pass. Subjects and rooms have no editor until step 15, so a section shows no subjects until Admin adds them. A subject with `has_laboratory` gets a second laboratory row per section (migration `20261025090000_laboratory_meetings.sql`, decision-log.md #20).

- [x] 9. **Assessment slip**
      Registrar issues it after the schedule is approved. Student can view and download it.
      Written, not yet run: migration `20261025080000_assessment_slip.sql`, checks in `supabase/gates_check.sql`, `features/assessment-slip/`, `/registrar/slips`, the student's `/slip` page, and the slip line in `features/next-step-card/`. Tick this step after `gates_check.sql`, lint, type check and the design gate pass. The slip is the light version with the fields the plan names (student number, name, program, section, subjects with professor, room and time, payment required or not); open question #2 stays open for the COR in step 11. "Download" is the browser's print dialog, which saves a PDF; no PDF library was added.

- [x] 10. **Payment**
      Per-course toggle (Admin and Finance), Finance records payment. Skipped when the toggle is off.
      Written, not yet run: migration `20261025100000_payment.sql` (`record_payment`, `payment_queue`, `my_payment_status`), checks in `supabase/gates_check.sql`, `features/payment/`, `/finance/payments` (tabs Pending, Cleared, Programs; the toggle lives on Programs), and the payment line in `features/next-step-card/`. Tick this step after `gates_check.sql`, lint, type check and the design gate pass. No partial payments, and the toggle only affects slips issued afterwards (decision-log.md #22).

- [x] 11. **COR**
      Registrar issues it after payment (or right after the slip when payment is not required). Student is enrolled.
      Written, not yet run: migration `20261025110000_cor.sql` (`enrollment_term`, `issue_cor`, `issue_all_ready_cors`, `certificate_of_registration`), checks in `supabase/gates_check.sql` (the older COR fixtures now set the term first), `features/cor/`, `/registrar/cors`, the student's `/cor` print page, and the enrolled state in `features/next-step-card/`. Tick this step after `gates_check.sql`, lint, type check and the design gate pass. Admin must set the school year and semester by SQL before any COR can be issued: `INSERT INTO enrollment_term (school_year, semester) VALUES ('2026-2027','1st');`. The COR follows PLP's layout but has no fee breakdown or fields the system does not hold (decision-log.md #21). Open question #2 (COR layout) is settled by this.

- [ ] 12. **Reschedules**
      Mass reschedule (Registrar or Admin) moves every affected student to the next available slot. Student request, Registrar approves or declines. Emails and next step cards.

- [ ] 13. **Audit log page**
      Admin only view of the append only log.

- [ ] 14. **Role dashboards**
      Applicant, Student, Registrar, Finance, Dean, Secretary, Professor and Admin home screens.

- [ ] 15. **Content population**
      Colleges, programs, subjects, rooms, staff accounts. Content task, do last so the schema is stable first.
