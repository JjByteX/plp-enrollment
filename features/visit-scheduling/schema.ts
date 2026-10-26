// features/visit-scheduling/schema.ts
//
// Input checks for a visit slot (step 6). The database enforces capacity,
// open/closed and program match; these checks give the Registrar a clear
// message before the request is sent.
//
// Slot input, as typed in the form:
//   programId     programs.id
//   slotDate      YYYY-MM-DD, not before today (Manila time)
//   startTime     HH:MM (24 hour)
//   endTime       HH:MM, after startTime
//   capacity      whole number, 1 or more
//   officeName    where to go, shown on the applicant's card
//   whatToBring   optional extra notes, shown after the checklist for the applicant's admission type

import { UUID, isRealDate, normalizeTime, text } from '@/lib/validate';
import { manilaToday } from '@/lib/format';

export { UUID, isRealDate } from '@/lib/validate';
export { formatSlotDate, manilaToday, windowLabel } from '@/lib/format';

export const MAX_CAPACITY = 500;
export const MAX_REASON = 200;

export type SlotInput = {
  programId: string;
  slotDate: string;
  startTime: string;
  endTime: string;
  capacity: number;
  officeName: string;
  whatToBring: string;
};

export type ParsedSlot = { ok: true; value: SlotInput } | { ok: false; reason: string };

export function parseSlotInput(raw: unknown, today: string = manilaToday()): ParsedSlot {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The slot details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const programId = text(body, 'programId');
  if (!UUID.test(programId)) return { ok: false, reason: 'Choose the program.' };

  const slotDate = text(body, 'slotDate');
  if (!isRealDate(slotDate)) return { ok: false, reason: 'Enter a real date.' };
  if (slotDate < today) return { ok: false, reason: 'The date cannot be in the past.' };

  const startTime = normalizeTime(text(body, 'startTime'));
  if (!startTime) return { ok: false, reason: 'Enter the start time.' };
  const endTime = normalizeTime(text(body, 'endTime'));
  if (!endTime) return { ok: false, reason: 'Enter the end time.' };
  if (endTime <= startTime) return { ok: false, reason: 'The end time must be after the start time.' };

  const capacity = body.capacity;
  if (typeof capacity !== 'number' || !Number.isInteger(capacity) || capacity < 1 || capacity > MAX_CAPACITY) {
    return { ok: false, reason: `Capacity must be a whole number from 1 to ${MAX_CAPACITY}.` };
  }

  const officeName = text(body, 'officeName');
  if (officeName.length === 0) return { ok: false, reason: 'Enter the office name.' };
  if (officeName.length > 100) return { ok: false, reason: 'The office name is longer than 100 characters.' };

  const whatToBring = text(body, 'whatToBring');
  if (whatToBring.length > 2000) return { ok: false, reason: 'The notes are longer than 2000 characters.' };

  return { ok: true, value: { programId, slotDate, startTime, endTime, capacity, officeName, whatToBring } };
}
