'use server';

// features/cor/actions.ts
//
// Registrar (or Admin) actions for issuing the COR. Each checks the caller
// first, then runs under the caller's own session so row level security
// applies and the audit log records who did it (decision-log.md #10). Issuing
// goes through database functions, so the COR and the student's notification
// are one transaction.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { UUID } from './schema';

export type CorActionResult = { ok: true; message: string } | { error: string };

const PAGE = '/registrar/cors';

async function requireStaff(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'registrar' || actor.role === 'admin') ? actor : null;
}

// Messages the database raises on purpose (P0001) are written for the
// Registrar, so show them. Anything else gets a plain message.
function failure(error: { code?: string; message: string }, fallback: string): { error: string } {
  if (error.code === 'P0001') return { error: error.message };
  return { error: fallback };
}

export async function issueCor(studentId: string): Promise<CorActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can issue a COR.' };
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { error: 'Choose a student.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('issue_cor', { p_student: studentId });
  if (error) return failure(error, 'The COR could not be issued.');

  revalidatePath(PAGE);
  return { ok: true, message: 'COR issued. The student is now officially enrolled.' };
}

export async function issueAllReadyCors(): Promise<CorActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can issue a COR.' };

  const supabase = createClient();
  const { data, error } = await supabase.rpc('issue_all_ready_cors');
  if (error) return failure(error, 'The CORs could not be issued. Try again.');

  const row = (Array.isArray(data) ? data[0] : data) as { issued?: number } | number | null;
  const issued = typeof row === 'number' ? row : (row?.issued ?? 0);

  revalidatePath(PAGE);
  return { ok: true, message: issued === 0 ? 'No COR is waiting.' : `${issued} CORs issued.` };
}
