// lib/supabase/client.ts
//
// Supabase client for Client Components (runs in the browser). It reads and
// writes the session cookies that middleware keeps fresh.
import { createBrowserClient } from '@supabase/ssr';

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
