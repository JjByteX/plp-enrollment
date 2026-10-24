# ci-cd.md

> Optional. Fill this in only if the project needs automated checks or deployment.

---
## AI RULES — READ FULLY BEFORE ANY ACTION
---

1. If "Needed" below is No → do nothing. If it is blank → ask the human.
   Never set up a pipeline on your own.
2. Read this entire file and architecture-notes.md before creating or
   changing any pipeline.
3. Match the project scale. Do not add steps, tools, or environments
   the project does not need.
4. Never touch secrets, credentials, or production config without
   human approval. Never put secrets in the repo.
5. Never deploy to production without human confirmation.
6. Log hard-to-reverse choices (platform, deploy strategy) in
   decision-log.md, following its filter.

---
## WHAT THIS IS
---

**CI (continuous integration):** every change is automatically checked
(lint, tests, build) before it is accepted.

**CD (continuous delivery / deployment):** a change that passes is
automatically shipped to an environment, without manual steps.

**Usually worth it when:** more than one person contributes, the code is
deployed repeatedly, tests exist, or manual deploys cause mistakes.

**Usually not needed when:** it is a solo prototype, there are no tests,
or it is deployed rarely.

---
## PROJECT REFERENCE
---

**Needed:**
[x] Yes   [ ] No   [ ] Later

**Platform:**
GitHub Actions (decided 2026-10-25)

**Checks on every change:**
Lint, type check, build, design gate, `supabase db reset` test of all migrations, `supabase db lint`, and SonarQube analysis. Security checks kept light (no dedicated security scanning beyond SonarQube defaults). No tests exist yet. Design gate: fails the build when components hardcode colors, spacing, radius or fonts instead of using `styles/tokens.ts`. SonarQube: SonarQube Cloud free plan (private repos up to 50k lines of code).

**Environments:**
Production only, plus Vercel preview deploys per branch (decided 2026-10-25).

**Deploy trigger:**
Merge to main deploys automatically. The same workflow validates the push, then applies database migrations to Supabase (decided 2026-10-25). Order: checks pass, then migrations apply to production Supabase, then the production deploy to Vercel runs from the same workflow (Vercel's own Git auto-deploy is turned off for main; preview deploys per branch stay on).

**Deploy target:**
Vercel (app) and Supabase (database migrations).

**Where secrets are stored:**
GitHub Actions secrets: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF`, `SONAR_TOKEN`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`. App runtime variables stay in Vercel environment variables. Never in the repo.

**Must never run automatically:**
Editing a migration already merged to main (forward-only, as in Lakbay Pasig: add a new migration instead). Production deploy and migration never run if any check fails.

**Known fragile steps:**
- Automatic migration of the production database: there is no staging database, so a bad migration hits live data first.
- Migrations live in `supabase/migrations/` (timestamped). The app has no `tsconfig.json` or `next.config` yet, so type check and build fail until the app scaffold exists.

---
