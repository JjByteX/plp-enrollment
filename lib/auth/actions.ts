'use server';

// lib/auth/actions.ts
//
// Server Actions for signing in, signing out and setting a password.
// Everything runs as the signed-in person's own Supabase session.
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/auth/session';
import { homePath, isRole } from '@/lib/auth/roles';
import { checkPassword, isEmail } from '@/lib/auth/validate';

type ActionError = { error: string };

// On success this redirects, so it only ever returns an error.
export async function signIn(email: string, password: string): Promise<ActionError> {
  if (!isEmail(email) || password.length === 0) {
    return { error: 'Enter your email and password.' };
  }

  const supabase = createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error || !data.user) {
    if (error?.status === 429) return { error: 'Too many attempts. Try again in a few minutes.' };
    return { error: 'Email or password is wrong.' };
  }

  // The same client now holds the new session, so this read runs as that person.
  const { data: row } = await supabase
    .from('users')
    .select('role, is_active')
    .eq('auth_id', data.user.id)
    .maybeSingle();

  if (!row || !row.is_active || !isRole(row.role)) {
    await supabase.auth.signOut();
    return { error: 'This account has no access to PLP Enrollment. Contact the Admin.' };
  }

  redirect(homePath(row.role));
}

export async function signOut(): Promise<void> {
  const supabase = createClient();
  await supabase.auth.signOut();
  redirect('/login');
}

// Used by /set-password after the emailed link has signed the person in.
export async function setPassword(password: string, confirm: string): Promise<ActionError> {
  const problem = checkPassword(password, confirm);
  if (problem) return { error: problem };

  const user = await getCurrentUser();
  if (!user) {
    return { error: 'This link has expired or the account has no access. Ask the Admin for a new link.' };
  }

  const supabase = createClient();
  const { error } = await supabase.auth.updateUser({ password });
  if (error) return { error: error.message };

  redirect(homePath(user.role));
}
