'use server';

// features/term-close/actions.ts
//
// The one action of step 21: close the current term. It checks the caller's role, then calls
// a database function that checks it again, refuses while any section subject that has students
// lacks Dean-approved grades, and decides each student's result. Messages the database raises
// on purpose (P0001) are shown as written.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failure } from '@/lib/failure';
import { getCurrentUser } from '@/lib/auth/session';
import { closeMessage, type CloseSummary } from './schema';

export type TermCloseResult = { ok: true; message: string } | { error: string };

const PAGES = ['/registrar/grades', '/registrar', '/secretary/schedule', '/dean', '/secretary', '/admin'];

export async function closeTerm(): Promise<TermCloseResult> {
  const actor = await getCurrentUser();
  if (!actor || (actor.role !== 'registrar' && actor.role !== 'admin')) {
    return { error: 'Only the Registrar can close a term.' };
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc('close_term');
  if (error) return failure(error, 'The term could not be closed.');

  const summary = (data ?? { promote: 0, review: 0, completed: 0 }) as CloseSummary;
  for (const page of PAGES) revalidatePath(page);
  return { ok: true, message: closeMessage(summary) };
}
