# architecture-notes.md

---
## AI RULES — READ FULLY BEFORE ANY ACTION
---

1. Read this entire file before proposing any structure, modifying
   any file, or debugging anything.
2. Project scale drives everything. Read the Scale field first.
   Do not propose a structure that exceeds what the scale requires.
3. Before touching any file → identify all files connected to it.
   This map is your reference. If a connection is not listed here,
   find it before proceeding — do not assume it is isolated.
4. Update this file only when the structure changes in a major way:
   a new module or feature, a tech stack change, a moved entry point,
   or a new key dependency. Do not update it for new files, renames,
   or small edits.
5. Never create folders or layers that the current scale does not
   justify. Do not over-architect small projects. Do not under-
   structure large ones.

---
## SCALE — READ THIS FIRST
---

**Project Scale:**
[x] Medium — multiple features, growing complexity, needs modularity

**Scale Guidelines the AI must follow:**

Small → near-flat structure. Minimal subfolders. Group only what
        genuinely needs grouping. No layers for their own sake.

Medium → feature-based grouping. Each feature owns its files.
         Shared utilities in one place. Clear separation of concerns
         without over-engineering.

Large → fully modular. Domain-driven. Each module is independently
        navigable. Explicit dependency boundaries. Documented entry
        points for every major section.

---
## PROJECT REFERENCE
---

**Project Type:**
Web app (staff- and student-facing), separate system from PLP Admissions with its own hosting, database, and logins.

**Tech Stack:**
- Frontend: Next.js (App Router) + React + Mantine UI
- Backend: Next.js API routes / Route Handlers (same codebase)
- Database: PostgreSQL via Supabase
- Auth: Supabase Auth (email/password; Applicants get a set-password email link per enrollment-plan.md's Admissions connection flow)
- Hosting: Vercel
- Fonts: Manrope (headings) and Plus Jakarta Sans (body) — exact pairing/weights to confirm when ux-ui-guidelines.md's typography rules are applied
- Other: Supabase Storage for uploaded documents (birth certificate, report card, IDs — Registrar/Admin visibility only per RBAC)

**Entry Points:**
- `app/layout.tsx` — root layout, font loading, Mantine provider
- `app/(public)/` — unauthenticated routes (set-password, login)
- `app/(portal)/layout.tsx` — authenticated shell (header, nav, "Your next step" card slot) per the Layout Shell rules in ux-ui-guidelines.md
- `app/api/admissions/intake/route.ts` — the one inbound webhook endpoint from PLP Admissions
- `lib/db.ts` — Postgres/Supabase client singleton

**Folder Structure (proposed — awaiting approval before creating):**
```
enrollment/
├── app/
│   ├── (public)/
│   │   ├── login/
│   │   └── set-password/
│   ├── (portal)/
│   │   ├── layout.tsx                 # shell: header, nav, next-step slot
│   │   ├── applicant/                 # Applicant's own status view
│   │   ├── student/                   # Student's own record, slip, COR, schedule
│   │   ├── registrar/                 # documents, schedules, slip/COR issuance, reschedules
│   │   ├── finance/                   # payment status, toggle (view/edit per RBAC)
│   │   ├── dean/                      # college students, sign-off
│   │   ├── secretary/                 # section/professor/room prep
│   │   ├── professor/                 # own subjects, class lists
│   │   └── admin/                     # accounts, settings, audit log, admissions connection
│   └── api/
│       ├── admissions/intake/         # inbound webhook from Admissions
│       ├── students/
│       ├── schedules/
│       ├── documents/
│       ├── payments/
│       ├── reschedules/
│       └── audit/
├── features/                          # feature-owned UI + logic, one folder per bounded feature
│   ├── admissions-intake/
│   ├── visit-scheduling/
│   ├── documents-and-numbering/
│   ├── section-scheduling/
│   ├── assessment-slip/
│   ├── payment/
│   ├── cor/
│   ├── reschedule-mass/
│   ├── reschedule-request/
│   └── next-step-card/
├── lib/                               # shared utilities: db client, auth helpers, rbac, audit-log writer
├── components/                        # shared, non-feature-specific UI (Mantine wrappers, tokens)
├── styles/                            # design tokens (colors, spacing, radius, padding — per ux-ui-guidelines.md)
├── docs/                              # project-brief, architecture-notes, constraints, decision-log, open-questions, ux-ui-guidelines, ci-cd, enrollment-plan
└── supabase/
    └── migrations/                    # timestamped SQL migrations (Supabase CLI layout)
```
Each feature folder under `features/` matches one row of the Module/Feature Map below — this keeps the Medium-scale rule (feature-based grouping, shared utilities in one place, no over-engineering) intact.

**Module / Feature Map:**
List the main modules or features and what each one is responsible for.
- Admissions Intake → Receives the one secure HTTPS call from PLP Admissions, validates shared secret and program code, creates/refreshes Applicant accounts, logs every request (success or failure).
- Visit Scheduling → Staff-defined visit slots per program; assigns students to slots; never student-selected.
- Document Receipt & Student Numbering → Registrar marks documents received; auto-assigns the one-time student number; promotes Applicant → Student.
- Section/Professor/Room Scheduling → College Secretary prepares sections, professors, rooms; Dean signs off on professor loading; Registrar approves.
- Assessment Slip → Issued by Registrar after schedule approval.
- Payment → Per-course toggle (Admin/Finance editable, Registrar/Dean view-only); Finance records payment; skipped if toggle is off.
- COR Issuance → Issued by Registrar after payment clearance (or immediately if payment not required); marks student enrolled.
- Reschedule (Mass) → Registrar/Admin-triggered, auto-moves all affected students, notifies via "next step" card + email.
- Reschedule (Student Request) → Student submits reason; Registrar approves/declines.
- RBAC / Access Control → Enforced at the database level per the Access table in enrollment-plan.md; deny by default.
- Audit Log → Records every reschedule, every money/schedule/student-number change, and every Admin action.
- "Your Next Step" Card → Persistent, on every relevant page, tells the user office/window/time/what to bring.

**Key Dependencies Between Files:**
Which files depend on which? What breaks if X changes?
(This is the map the AI uses before touching anything)
- [file/module] → depends on → [file/module]
- [file/module] → depends on → [file/module]

**What Must Never Be Touched Without Human Approval:**
(e.g. auth logic, payment flows, database schema, config files)

**Known Fragile Areas:**
Areas of the codebase that have caused bugs before or require
extra care when modified.

---
## STRUCTURE CHANGE LOG
---
AI: log only major structural changes (rule 4). One sentence per cell.

| Date | Change | Reason |
|------|--------|--------|
| 2026-10-25 | Framework and plan .md files moved into `docs/` (README.md and LICENSE stay at root). | Keeps the project root clean for app code. |
| 2026-10-25 | Migrations moved from `db/migrations/` to `supabase/migrations/` (timestamped). | Supabase CLI and the CI/CD workflow expect this layout. |

---
