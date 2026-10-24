// lib/supabase/admin.ts
//
// Supabase client with the service role key. It bypasses row level security.
// Server only. Used for one thing in step 4: creating the auth user when an
// Admin creates a staff account (app/(portal)/admin/accounts/actions.ts).
// The caller must already have checked that the signed-in person is an Admin.
import { createClient } from '@supabase/supabase-js';

export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is not set. Add it to .env.local and to the Vercel environment variables.');
  }

  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
