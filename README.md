# PLP Enrollment

Enrollment system for newly admitted PLP students. It picks up where the separate PLP Admissions system stops: it receives an admitted applicant, then carries them through document receipt, an automatic student number, schedule and professor setup, optional payment, and the final COR.

It is its own system with its own hosting, database and logins. The only link to PLP Admissions is one secure HTTPS call from Admissions to Enrollment.

**Status:** foundation stage. The database schema, CI/CD pipeline and design tokens exist. The Next.js app itself is not scaffolded yet. See `docs/build-order.md`.

## Stack

- Next.js (App Router), React, Mantine UI
- PostgreSQL on Supabase (database, auth, file storage)
- Vercel hosting
- Manrope (headings) and Plus Jakarta Sans (body)

## Roles

Applicant, Student, Registrar, Finance, Dean, College Secretary, Professor, Admin. Access is enforced in the database with row level security, not just hidden in screens. See `docs/enrollment-plan.md`.

## Folders

| Folder | What is in it |
|--------|---------------|
| `app/` | Next.js routes and layouts |
| `styles/` | Design tokens (`tokens.ts`) and the Mantine theme |
| `lib/` | Shared code, such as the database client |
| `supabase/` | Config and SQL migrations (`migrations/`), plus `gates_check.sql` |
| `scripts/` | Small check scripts, such as the design gate |
| `.github/workflows/` | CI/CD pipeline |
| `docs/` | Plan, rules and decisions (see below) |

More folders (`features/`, `components/`) are planned in `docs/architecture-notes.md`.

## Local setup

You need Node 20 and Docker (for the local Supabase database).

```
npm install
cp .env.example .env.local     # then fill in the values
npx supabase start             # local database
npm run db:reset               # applies every migration from scratch
```

Run `npm run db:reset` after pulling new migration files. Never edit a migration already merged to main: add a new one with `npx supabase migration new <name>`.

## Checks

```
npm run lint
npm run typecheck
npm run build
npm run design-gate     # fails on hardcoded colors, fonts, spacing or radius
npm run db:lint
```

On every pull request and push to main, GitHub Actions runs all of these, plus a full migration reset and SonarQube. A push to main that passes then applies migrations to production Supabase and deploys to Vercel. Details and the list of required secrets are in `docs/ci-cd.md`.

## Docs

| File | Purpose |
|------|---------|
| `docs/enrollment-plan.md` | The decided plan: process, roles, access, reschedules |
| `docs/project-brief.md` | What is being built and what done looks like |
| `docs/architecture-notes.md` | Stack, folder structure, how modules connect |
| `docs/build-order.md` | What to build, in order |
| `docs/decision-log.md` | Major decisions and why |
| `docs/open-questions.md` | Questions that need a human answer |
| `docs/constraints.md` | Rules the AI must never break |
| `docs/ux-ui-guidelines.md` | Rules for every UI decision |
| `docs/ci-cd.md` | Pipeline, environments, secrets |

## Working with the AI

This project follows the Project Foundation framework. Give the AI the `docs/` files and say **start**. It reads the rules first, asks about anything left blank, checks which files are connected before changing anything, and logs major decisions instead of silently overriding them. Review what it builds and push back where it misses.

## License

MIT
