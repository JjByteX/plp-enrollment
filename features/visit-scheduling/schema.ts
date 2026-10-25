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

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

// Today's date in Manila, as YYYY-MM-DD. Slots are Manila dates.
export function manilaToday(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

function text(raw: Record<string, unknown>, key: string): string {
  const value = raw[key];
  return typeof value === 'string' ? value.trim() : '';
}

export function isRealDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

// Accepts HH:MM or HH:MM:SS (the database returns seconds) and returns HH:MM.
function normalizeTime(value: string): string | null {
  const match = /^([01]\d|2[0-3]):([0-5]\d)(?::00)?$/.exec(value);
  return match ? `${match[1]}:${match[2]}` : null;
}

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

// "Mon, Nov 2, 2026" from a YYYY-MM-DD slot date. Fixed to UTC so the server
// and the browser print the same text.
export function formatSlotDate(value: string): string {
  return new Intl.DateTimeFormat('en-PH', {
    weekday: 'short',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${value}T00:00:00Z`));
}

// "9:00 AM to 12:00 PM" from two HH:MM values, the same wording the
// database writes into notifications.window_label.
export function windowLabel(startTime: string, endTime: string): string {
  const format = (value: string) => {
    const [h, m] = value.split(':').map(Number);
    const hour = h % 12 === 0 ? 12 : h % 12;
    return `${hour}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
  };
  return `${format(startTime)} to ${format(endTime)}`;
}
