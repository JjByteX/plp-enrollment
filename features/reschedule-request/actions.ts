'use server';

// features/reschedule-request/actions.ts
//
// An applicant or student asks to move their visit; the Registrar (or Admin)
// approves or declines. Every action checks the caller first, then runs under
// the caller's own session so row level security applies and the audit log
// records who did it (decision-log.md #10). Asking and deciding go through
// database functions, so the request, the move and the person's notification
// are one transaction. The person never picks a slot (decision-log.md #5).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failureWith } from '@/lib/failure';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { parseDecisionInput, parseReason, type DecisionInput } from './schema';

export type RescheduleActionResult = { ok: true; message: string } | { error: string };

const PAGE = '/registrar/reschedules';

async function requireStaff(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'registrar' || actor.role === 'admin') ? actor : null;
}

async function requireRequester(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'applicant' || actor.role === 'student') ? actor : null;
}

// 23505 is a second request while one is already waiting.
const failure = failureWith({ '23505': 'You already have a reschedule request waiting for the Registrar.' });

// The applicant or student sends a reason. The next step card is rendered by
// the portal layout, so the whole layout is refreshed to show the waiting state.
export async function requestReschedule(reason: string): Promise<RescheduleActionResult> {
  const actor = await requireRequester();
  if (!actor) return { error: 'Only an applicant or student can request a reschedule.' };

  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('request_reschedule', { p_reason: parsed.value });
  if (error) return failure(error, 'The request could not be sent. Try again.');

  revalidatePath('/', 'layout');
  return { ok: true, message: 'Request sent. The Registrar will answer on your next step card.' };
}

// Approve moves the visit (to the chosen slot, or the next open slot on another
// date) and the person gets the usual visit moved notification. Decline needs
// a note, which the person is shown.
export async function decideReschedule(input: DecisionInput): Promise<RescheduleActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can answer a reschedule request.' };

  const parsed = parseDecisionInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { requestId, approve, slotId, note } = parsed.value;

  const supabase = createClient();
  const { error } = await supabase.rpc('decide_reschedule', {
    p_request: requestId,
    p_approve: approve,
    p_slot: slotId,
    p_note: note.length > 0 ? note : null,
  });
  if (error) return failure(error, 'The request could not be answered. Try again.');

  revalidatePath(PAGE);
  revalidatePath('/registrar/visits');
  return {
    ok: true,
    message: approve
      ? 'Request approved. The visit was moved and the person was told.'
      : 'Request declined. The person was told.',
  };
}
