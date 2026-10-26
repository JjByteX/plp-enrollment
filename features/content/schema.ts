// features/content/schema.ts
//
// Input checks and labels for the content editors (step 15): subjects, rooms
// and the current term. No server imports, so client components can use it.
// The database enforces the real rules (Admin only, unique codes and names,
// a school year followed by the next one); these checks give Admin a clear
// message before the request is sent.
//
// Subject input:  programId, code (1 to 30), title (1 to 200), units (0 to 99.9,
//                 one decimal), yearLevel (1 to 6), semester (1st, 2nd or summer),
//                 hasLaboratory, offeredInSummer
// Room input:     name (1 to 80), capacity (whole number from 1, or none), collegeId (or none)
// Term input:     schoolYear (2026-2027), semester (1st, 2nd or summer)
export { UUID } from '@/features/visit-scheduling/schema';
export { SEMESTER_LABEL, type Semester } from '@/features/cor/schema';
import { UUID } from '@/features/visit-scheduling/schema';
import { MAX_YEAR, type Parsed } from '@/features/section-scheduling/schema';
import type { Semester } from '@/features/cor/schema';

export { MAX_YEAR };
export const MAX_CODE = 30;
export const MAX_TITLE = 200;
export const MAX_ROOM_NAME = 80;
export const MAX_ROOM_CAPACITY = 5000;
export const MAX_UNITS = 99.9; // numeric(3,1)

export type ContentTab = 'subjects' | 'rooms' | 'term' | 'grading';

export function parseTab(raw: unknown): ContentTab {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return value === 'rooms' || value === 'term' || value === 'grading' ? value : 'subjects';
}

function text(raw: Record<string, unknown>, key: string): string {
  const value = raw[key];
  return typeof value === 'string' ? value.trim() : '';
}

function asObject(raw: unknown): Record<string, unknown> | null {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw) ? (raw as Record<string, unknown>) : null;
}

export type SubjectFields = { code: string; title: string; units: number; hasLaboratory: boolean; offeredInSummer: boolean };
export type SubjectInput = SubjectFields & { programId: string; yearLevel: number; semester: Semester };

function parseSubjectFields(body: Record<string, unknown>): Parsed<SubjectFields> {
  const code = text(body, 'code');
  if (code.length === 0) return { ok: false, reason: 'Enter the subject code.' };
  if (code.length > MAX_CODE) return { ok: false, reason: `The code is longer than ${MAX_CODE} characters.` };

  const title = text(body, 'title');
  if (title.length === 0) return { ok: false, reason: 'Enter the subject title.' };
  if (title.length > MAX_TITLE) return { ok: false, reason: `The title is longer than ${MAX_TITLE} characters.` };

  const units = body.units;
  if (
    typeof units !== 'number' ||
    !Number.isFinite(units) ||
    units < 0 ||
    units > MAX_UNITS ||
    Math.abs(units * 10 - Math.round(units * 10)) > 1e-6
  ) {
    return { ok: false, reason: `Units must be from 0 to ${MAX_UNITS}, with one decimal at most.` };
  }

  return {
    ok: true,
    value: {
      code,
      title,
      units,
      hasLaboratory: body.hasLaboratory === true,
      offeredInSummer: body.offeredInSummer === true,
    },
  };
}

// Adding a subject also needs its program and year level. A subject with no
// year level would never reach a section, so the year level is required.
export function parseSubjectInput(raw: unknown): Parsed<SubjectInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The subject details are missing.' };

  const programId = text(body, 'programId');
  if (!UUID.test(programId)) return { ok: false, reason: 'Choose the program.' };

  const yearLevel = body.yearLevel;
  if (typeof yearLevel !== 'number' || !Number.isInteger(yearLevel) || yearLevel < 1 || yearLevel > MAX_YEAR) {
    return { ok: false, reason: `Year level must be a whole number from 1 to ${MAX_YEAR}.` };
  }

  const semester = text(body, 'semester');
  if (semester !== '1st' && semester !== '2nd' && semester !== 'summer') {
    return { ok: false, reason: 'Choose the semester.' };
  }

  const fields = parseSubjectFields(body);
  if (!fields.ok) return fields;
  // A summer subject runs in summer already, so the summer flag does not apply.
  const offeredInSummer = semester === 'summer' ? false : fields.value.offeredInSummer;
  return { ok: true, value: { ...fields.value, offeredInSummer, programId, yearLevel, semester } };
}

// Editing a subject changes its code, title, units, laboratory flag and summer
// flag. The program, year level and semester stay, because sections were filled
// from them.
export function parseSubjectEdit(raw: unknown): Parsed<SubjectFields> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The subject details are missing.' };
  return parseSubjectFields(body);
}

export type RoomInput = { name: string; capacity: number | null; collegeId: string | null };

export function parseRoomInput(raw: unknown): Parsed<RoomInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The room details are missing.' };

  const name = text(body, 'name');
  if (name.length === 0) return { ok: false, reason: 'Enter the room name.' };
  if (name.length > MAX_ROOM_NAME) return { ok: false, reason: `The name is longer than ${MAX_ROOM_NAME} characters.` };

  let capacity: number | null = null;
  if (body.capacity !== null && body.capacity !== undefined && body.capacity !== '') {
    const value = body.capacity;
    if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > MAX_ROOM_CAPACITY) {
      return { ok: false, reason: `Capacity must be a whole number from 1 to ${MAX_ROOM_CAPACITY}, or left empty.` };
    }
    capacity = value;
  }

  let collegeId: string | null = null;
  if (body.collegeId !== null && body.collegeId !== undefined && body.collegeId !== '') {
    if (typeof body.collegeId !== 'string' || !UUID.test(body.collegeId)) {
      return { ok: false, reason: 'Choose a college from the list, or leave it empty.' };
    }
    collegeId = body.collegeId;
  }

  return { ok: true, value: { name, capacity, collegeId } };
}

export type TermInput = { schoolYear: string; semester: Semester };

export function parseTermInput(raw: unknown): Parsed<TermInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The term details are missing.' };

  const schoolYear = text(body, 'schoolYear');
  const match = /^(\d{4})-(\d{4})$/.exec(schoolYear);
  if (!match) return { ok: false, reason: 'Write the school year like 2026-2027.' };
  if (Number(match[2]) !== Number(match[1]) + 1) {
    return { ok: false, reason: 'The second year must follow the first, like 2026-2027.' };
  }

  const semester = text(body, 'semester');
  if (semester !== '1st' && semester !== '2nd' && semester !== 'summer') {
    return { ok: false, reason: 'Choose the semester.' };
  }
  return { ok: true, value: { schoolYear, semester } };
}
