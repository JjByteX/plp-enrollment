'use server';

// features/prerequisites/actions.ts
//
// Actions for prerequisites and credits (step 20). Each checks the caller's
// role, then calls a database function that checks it again. Admin and the Dean
// set prerequisites; the Dean or the College Secretary records a credit and the
// Registrar approves or rejects it. Messages the database raises on purpose
// (P0001) are shown as written.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failure } from '@/lib/failure';
import { getCurrentUser } from '@/lib/auth/session';
import type { Role } from '@/lib/auth/roles';
import { getCreditOverview } from './queries';
import { UUID, parseCreditInput, parsePrerequisiteInput, parseReason, type CreditOverview } from './schema';

export type PrerequisiteActionResult = { ok: true; message: string } | { error: string };

const PAGES = [
  '/admin/prerequisites',
  '/dean/prerequisites',
  '/secretary/prerequisites',
  '/registrar/prerequisites',
  '/registrar/grades',
];

async function allowed(roles: readonly Role[]): Promise<boolean> {
  const actor = await getCurrentUser();
  return actor !== null && roles.includes(actor.role);
}

function done(message: string): PrerequisiteActionResult {
  for (const page of PAGES) revalidatePath(page);
  return { ok: true, message };
}

const CREDIT_RECORDERS: readonly Role[] = ['dean', 'college_secretary', 'admin'];
const CREDIT_READERS: readonly Role[] = ['dean', 'college_secretary', 'registrar', 'admin'];
const REGISTRAR: readonly Role[] = ['registrar', 'admin'];

export async function savePrerequisites(input: unknown): Promise<PrerequisiteActionResult> {
  if (!(await allowed(['dean', 'admin']))) return { error: 'Only Admin or the Dean of this college can set prerequisites.' };
  const parsed = parsePrerequisiteInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('save_prerequisites', {
    p_subject: parsed.value.subjectId,
    p_required: parsed.value.requiredIds,
  });
  if (error) return failure(error, 'The prerequisites could not be saved.');
  return done('Prerequisites saved.');
}

// The credits of one student and the subjects a credit could still be recorded for. Reads only.
export async function loadCreditOverview(studentId: string): Promise<CreditOverview | { error: string }> {
  if (!(await allowed(CREDIT_READERS))) return { error: 'You cannot read credits.' };
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { error: 'That student was not found.' };
  const overview = await getCreditOverview(studentId);
  return overview ?? { error: 'The credits could not be read.' };
}

export async function recordCredit(input: unknown): Promise<PrerequisiteActionResult> {
  if (!(await allowed(CREDIT_RECORDERS))) return { error: 'Only the Dean or the College Secretary can record a credit.' };
  const parsed = parseCreditInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('record_credit', {
    p_student: parsed.value.studentId,
    p_subject: parsed.value.subjectId,
    p_reason: parsed.value.reason,
  });
  if (error) return failure(error, 'The credit could not be recorded.');
  return done('Credit recorded. It waits for the Registrar.');
}

export async function approveCredit(creditId: string): Promise<PrerequisiteActionResult> {
  if (!(await allowed(REGISTRAR))) return { error: 'Only the Registrar can approve a credit.' };
  if (typeof creditId !== 'string' || !UUID.test(creditId)) return { error: 'That credit was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('approve_credit', { p_credit: creditId });
  if (error) return failure(error, 'The credit could not be approved.');
  return done('Credit approved. It now counts as a pass.');
}

export async function rejectCredit(creditId: string, reason: string): Promise<PrerequisiteActionResult> {
  if (!(await allowed(REGISTRAR))) return { error: 'Only the Registrar can reject a credit.' };
  if (typeof creditId !== 'string' || !UUID.test(creditId)) return { error: 'That credit was not found.' };
  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('reject_credit', { p_credit: creditId, p_reason: parsed.value });
  if (error) return failure(error, 'The credit could not be rejected.');
  return done('Credit rejected.');
}
