# build-order.md

What to build, in order. Each step assumes the ones before it exist. Tick a step only when it works.

- [x] 1. **CI/CD and project scaffold files**
      GitHub Actions workflow, lint, design gate, Sonar config, Supabase config, tokens, theme, fonts. See `docs/ci-cd.md`. The Next.js scaffold (`tsconfig.json`, `next.config`) is still missing.

- [ ] 2. **Next.js scaffold**
      `tsconfig.json`, `next.config`, root layout, Mantine provider, folder structure from `architecture-notes.md`. Makes type check and build pass in CI.

- [ ] 3. **Database schema and RLS**
      `supabase/migrations/20261025000000_init.sql` written. Gates and row level security checked on a local Postgres 16 with `supabase/gates_check.sql`; not yet run through the Supabase CLI. Follow-up migration `20261025020000_...` adds the YY-NNNNN student number, seeds the 7 colleges and 13 programs, and lets Applicants request a reschedule. Schema first, no UI yet.

- [ ] 4. **Auth and roles**
      Supabase Auth, staff accounts created by Admin only, set-password link for Applicants. Decide how server code identifies the user to the database (see open-questions.md).

- [ ] 5. **Admissions intake**
      `app/api/admissions/intake/route.ts`: shared secret check, program code check, create or refresh Applicant, log every request. Admin page: view requests, resend a failed one, switch the connection on or off.

- [ ] 6. **Visit scheduling**
      Registrar sets up slots (date, time window, capacity per program) and assigns applicants. "Your next step" card slot in the portal shell.

- [ ] 7. **Documents and student numbering**
      Registrar uploads and marks documents received. Student number assigned automatically, Applicant becomes Student.

- [ ] 8. **Section, professor and room scheduling**
      Secretary prepares, Dean signs off professor loading, Registrar approves. Students placed in sections.

- [ ] 9. **Assessment slip**
      Registrar issues it after the schedule is approved. Student can view and download it.

- [ ] 10. **Payment**
      Per-course toggle (Admin and Finance), Finance records payment. Skipped when the toggle is off.

- [ ] 11. **COR**
      Registrar issues it after payment (or right after the slip when payment is not required). Student is enrolled.

- [ ] 12. **Reschedules**
      Mass reschedule (Registrar or Admin) moves every affected student to the next available slot. Student request, Registrar approves or declines. Emails and next step cards.

- [ ] 13. **Audit log page**
      Admin only view of the append only log.

- [ ] 14. **Role dashboards**
      Applicant, Student, Registrar, Finance, Dean, Secretary, Professor and Admin home screens.

- [ ] 15. **Content population**
      Colleges, programs, subjects, rooms, staff accounts. Content task, do last so the schema is stable first.
