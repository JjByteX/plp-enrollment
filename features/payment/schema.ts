// features/payment/schema.ts
//
// Input checks and labels for payment (step 10). No server imports, so client
// components can use it. The database enforces the real rules (Finance or
// Admin only, one payment per student, paid covers due); these checks give
// Finance a clear message before the request is sent.
//
// Payment input, as typed in the form:
//   studentId   students.id
//   amountDue   pesos, 0 or more, at most 2 decimals
//   amountPaid  pesos, same limits, must cover the amount due (no partial payments)
//   receiptNo   required when something was paid, up to MAX_RECEIPT characters

export { UUID } from '@/lib/validate';
import { UUID, parseChoice, type Parsed } from '@/lib/validate';

export const MAX_RECEIPT = 60;
export const MAX_AMOUNT = 9999999999.99; // numeric(12,2)

export type PaymentTab = 'pending' | 'cleared' | 'programs';

export type PaymentInput = {
  studentId: string;
  amountDue: number;
  amountPaid: number;
  receiptNo: string;
};

export function parseTab(raw: unknown): PaymentTab {
  return parseChoice(raw, ['pending', 'cleared', 'programs'], 'pending');
}

function isMoney(value: unknown): value is number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > MAX_AMOUNT) return false;
  return Math.abs(value * 100 - Math.round(value * 100)) < 1e-6; // at most 2 decimals
}

export function parsePaymentInput(raw: unknown): Parsed<PaymentInput> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The payment details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const studentId = typeof body.studentId === 'string' ? body.studentId.trim() : '';
  if (!UUID.test(studentId)) return { ok: false, reason: 'Choose a student.' };

  if (!isMoney(body.amountDue)) return { ok: false, reason: 'Enter the amount due in pesos, up to 2 decimals.' };
  if (!isMoney(body.amountPaid)) return { ok: false, reason: 'Enter the amount paid in pesos, up to 2 decimals.' };
  const amountDue = body.amountDue;
  const amountPaid = body.amountPaid;
  if (amountPaid < amountDue) return { ok: false, reason: 'The amount paid must cover the amount due.' };

  const receiptNo = typeof body.receiptNo === 'string' ? body.receiptNo.trim() : '';
  if (receiptNo.length > MAX_RECEIPT) {
    return { ok: false, reason: `The receipt number is longer than ${MAX_RECEIPT} characters.` };
  }
  if (amountPaid > 0 && receiptNo.length === 0) return { ok: false, reason: 'Enter the receipt number.' };

  return { ok: true, value: { studentId, amountDue, amountPaid, receiptNo } };
}
