// features/correct-student-details/schema.ts
//
// Input checks for correcting a student's name or email after promotion. The
// database repeats every rule and decides who may do it
// (20261025200000_correct_student_details.sql); these checks give a clear
// message before the request is sent. No server imports, so client components
// can use it.
//
// Input:
//   applicantId   applicants.id of the student
//   fullName      2 to 150 characters after trimming and collapsing spaces
//   email         a valid address, stored lower case
//   reason        1 to 500 characters after trimming

import { isEmail } from '@/lib/auth/validate';
import { parseReason } from '@/features/reschedule-request/schema';
import { UUID } from '@/features/visit-scheduling/schema';

export const MAX_NAME = 150;
export const MIN_NAME = 2;

export type CorrectInput = { applicantId: string; fullName: string; email: string; reason: string };

export type ParsedCorrect = { ok: true; value: CorrectInput } | { ok: false; reason: string };

export function cleanName(raw: string): string {
  return raw.trim().replace(/\s+/g, ' ');
}

export function parseCorrectInput(raw: unknown): ParsedCorrect {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The correction is missing.' };
  }
  const body = raw as Record<string, unknown>;

  const applicantId = typeof body.applicantId === 'string' ? body.applicantId.trim() : '';
  if (!UUID.test(applicantId)) return { ok: false, reason: 'Choose a student.' };

  const fullName = typeof body.fullName === 'string' ? cleanName(body.fullName) : '';
  if (fullName.length < MIN_NAME || fullName.length > MAX_NAME) return { ok: false, reason: 'Enter the full name.' };

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (!isEmail(email)) return { ok: false, reason: 'Enter a valid email address.' };

  const reason = parseReason(body.reason);
  if (!reason.ok) return reason;

  return { ok: true, value: { applicantId, fullName, email, reason: reason.value } };
}
