'use server';

// features/payment/actions.ts
//
// Finance (or Admin) actions for payment. Each checks the caller first, then
// runs under the caller's own session so row level security applies and the
// audit log records who did it (decision-log.md #10). Recording goes through
// a database function, so the cleared payment and the student's notification
// are one transaction. The toggle is a direct update: row level security lets
// only Finance and Admin change it, and a trigger audit-logs the change.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failure } from '@/lib/failure';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { UUID, parsePaymentInput } from './schema';

export type PaymentActionResult = { ok: true; message: string } | { error: string };

const PAGE = '/finance/payments';

async function requireFinance(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'finance' || actor.role === 'admin') ? actor : null;
}

export async function recordPayment(input: unknown): Promise<PaymentActionResult> {
  const actor = await requireFinance();
  if (!actor) return { error: 'Only Finance or Admin can record a payment.' };

  const parsed = parsePaymentInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { studentId, amountDue, amountPaid, receiptNo } = parsed.value;

  const supabase = createClient();
  const { error } = await supabase.rpc('record_payment', {
    p_student: studentId,
    p_amount_due: amountDue,
    p_amount_paid: amountPaid,
    p_receipt_no: receiptNo,
  });
  if (error) return failure(error, 'The payment could not be recorded.');

  revalidatePath(PAGE);
  return { ok: true, message: 'Payment recorded. The student was told.' };
}

export async function setPaymentRequired(programId: string, required: boolean): Promise<PaymentActionResult> {
  const actor = await requireFinance();
  if (!actor) return { error: 'Only Finance or Admin can change this.' };
  if (typeof programId !== 'string' || !UUID.test(programId) || typeof required !== 'boolean') {
    return { error: 'Choose a program.' };
  }

  const supabase = createClient();
  const { data, error } = await supabase
    .from('program_payment_settings')
    .update({ payment_required: required })
    .eq('program_id', programId)
    .select('program_id');
  if (error) return failure(error, 'The setting could not be saved.');
  if (!data || data.length === 0) return { error: 'That program was not found.' };

  revalidatePath(PAGE);
  return {
    ok: true,
    message: required
      ? 'Payment is now required. It applies to slips issued from now on.'
      : 'Payment is no longer required. It applies to slips issued from now on.',
  };
}
