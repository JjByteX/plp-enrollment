// features/withdraw-enrollment/schema.ts
//
// Input checks for withdrawing an enrollment (step 17). The database decides
// who may withdraw whom and does the whole release in one transaction
// (20261025190000_withdrawals.sql); these checks give a clear message before
// the request is sent. No server imports, so client components can use it.
//
// Withdraw input:
//   applicantId   applicants.id (staff only; a person withdrawing themselves sends none)
//   reason        1 to 500 characters after trimming
//
// Confirmation: the person types a word (themselves) or the identifying number
// of the person being withdrawn (staff). Case and spacing do not matter.

export { MAX_REASON, UUID, parseReason } from '@/lib/validate';
import { UUID, parseReason } from '@/lib/validate';

// What a student or applicant types to confirm withdrawing themselves.
export const CONFIRM_WORD = 'withdraw';

export function confirmMatches(typed: string, expected: string): boolean {
  const normalize = (text: string) => text.trim().replace(/\s+/g, ' ').toLowerCase();
  const wanted = normalize(expected);
  return wanted.length > 0 && normalize(typed) === wanted;
}

export type WithdrawInput = { applicantId: string; reason: string };

export type ParsedWithdraw = { ok: true; value: WithdrawInput } | { ok: false; reason: string };

export function parseWithdrawInput(raw: unknown): ParsedWithdraw {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The withdrawal is missing.' };
  }
  const body = raw as Record<string, unknown>;

  const applicantId = typeof body.applicantId === 'string' ? body.applicantId.trim() : '';
  if (!UUID.test(applicantId)) return { ok: false, reason: 'Choose a person to withdraw.' };

  const reason = parseReason(body.reason);
  if (!reason.ok) return reason;

  return { ok: true, value: { applicantId, reason: reason.value } };
}
