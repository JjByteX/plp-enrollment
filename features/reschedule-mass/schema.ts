// features/reschedule-mass/schema.ts
//
// Input checks for a mass reschedule (step 12). The database checks the role,
// the date, that something is booked and moves each person; these checks give
// the Registrar a clear message before the request is sent. No server imports,
// so client components can use it.
//
// Input, as typed in the form:
//   date        YYYY-MM-DD, the affected date, not before today (Manila time)
//   programId   programs.id, or null for every program
//   officeName  one office on that date, or null for every office
//   reason      1 to 500 characters, kept in the audit log and the record

export { UUID, formatSlotDate, isRealDate, manilaToday } from '@/features/visit-scheduling/schema';
export { MAX_REASON } from '@/features/reschedule-request/schema';
import { UUID, isRealDate, manilaToday } from '@/features/visit-scheduling/schema';
import { parseReason } from '@/features/reschedule-request/schema';

export type MassInput = {
  date: string;
  programId: string | null;
  officeName: string | null;
  reason: string;
};

export type ParsedMass = { ok: true; value: MassInput } | { ok: false; reason: string };

export function parseMassInput(raw: unknown, today: string = manilaToday()): ParsedMass {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const date = typeof body.date === 'string' ? body.date.trim() : '';
  if (date.length === 0) return { ok: false, reason: 'Choose the affected date.' };
  if (!isRealDate(date)) return { ok: false, reason: 'Enter a real date.' };
  if (date < today) return { ok: false, reason: 'The date cannot be in the past.' };

  let programId: string | null = null;
  if (typeof body.programId === 'string' && body.programId.trim().length > 0) {
    programId = body.programId.trim();
    if (!UUID.test(programId)) return { ok: false, reason: 'Choose a valid program.' };
  }

  let officeName: string | null = null;
  if (typeof body.officeName === 'string' && body.officeName.trim().length > 0) {
    officeName = body.officeName.trim();
    if (officeName.length > 100) return { ok: false, reason: 'The office name is longer than 100 characters.' };
  }

  const reason = parseReason(body.reason);
  if (!reason.ok) return { ok: false, reason: reason.reason };

  return { ok: true, value: { date, programId, officeName, reason: reason.value } };
}

// "1 visit", "3 visits".
export function visitCount(count: number): string {
  return `${count} ${count === 1 ? 'visit' : 'visits'}`;
}
