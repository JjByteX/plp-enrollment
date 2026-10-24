// lib/supabase/server.ts
//
// Supabase client for Server Components, Server Actions and Route Handlers.
// It carries the signed-in person's session, so the database sees that
// person (auth.uid()) and row level security applies. See decision-log.md #10.
//
// Create one per request. Never keep it in a module-level variable.
// Next 14: cookies() is synchronous. On Next 15 and later it becomes async.
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export function createClient() {
  const cookieStore = cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
          } catch {
            // Called from a Server Component, which cannot write cookies.
            // Safe to ignore: middleware refreshes the session.
          }
        },
      },
    }
  );
}
