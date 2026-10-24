// lib/db.ts
//
// Postgres client (Supabase transaction pooler). Mirrors the connection
// pattern used by the PLP Admissions system (config/db.php) — same
// Supabase/Postgres setup, separate project and database.
import { Pool } from 'pg';

declare global {
  // eslint-disable-next-line no-var
  var __enrollmentDbPool: Pool | undefined;
}

function createPool(): Pool {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error(
      'DATABASE_URL is not set. Copy .env.example to .env.local and fill in your Supabase connection string.'
    );
  }

  return new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false }, // Supabase pooler requires SSL
    max: 10,
  });
}

// Reuse the pool across hot reloads in dev and across invocations on Vercel.
export const db: Pool = global.__enrollmentDbPool ?? createPool();
if (process.env.NODE_ENV !== 'production') {
  global.__enrollmentDbPool = db;
}
