'use server';

// features/withdraw-enrollment/actions.ts
//
// An applicant or student withdraws themselves, or the Registrar (or Admin)
// withdraws someone. Every action checks the caller first, then runs under the
// caller's own session so row level security applies and the audit log records
// who did it (decision-log.md #10). Both go through one database function, so
// the visit slot, the section seat, the pending payment and the person's
// notification are released in one transaction (decision-log.md #30).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failure } from '@/lib/failure';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { parseReason, parseWithdrawInput, type WithdrawInput } from './schema';

export type WithdrawActionResult = { ok: true; message: string } | { error: string };

async function requireStaff(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'registrar' || actor.role === 'admin') ? actor : null;
}

async function requireStudentOrApplicant(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'applicant' || actor.role === 'student') ? actor : null;
}

// The person withdraws themselves. The next step card is rendered by the
// portal layout, so the whole layout is refreshed to show the withdrawn state.
export async function withdrawMyEnrollment(reason: string): Promise<WithdrawActionResult> {
  const actor = await requireStudentOrApplicant();
  if (!actor) return { error: 'Only an applicant or student can withdraw their own enrollment.' };

  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('withdraw_my_enrollment', { p_reason: parsed.value });
  if (error) return failure(error, 'Your enrollment could not be withdrawn. Try again.');

  revalidatePath('/', 'layout');
  return { ok: true, message: 'Your enrollment was withdrawn.' };
}

// The Registrar or Admin withdraws someone at any stage, including after a
// COR. The person is told, with the reason. Many pages change (visit slots,
// section seats, queues, dashboards), so the whole layout is refreshed.
export async function withdrawApplicant(input: WithdrawInput): Promise<WithdrawActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can withdraw an applicant.' };

  const parsed = parseWithdrawInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('withdraw_applicant', {
    p_applicant: parsed.value.applicantId,
    p_reason: parsed.value.reason,
  });
  if (error) return failure(error, 'The withdrawal could not be recorded. Try again.');

  revalidatePath('/', 'layout');
  return { ok: true, message: 'Withdrawn. The person was told and their visit slot and seat were released.' };
}
