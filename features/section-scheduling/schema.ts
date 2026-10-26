// features/section-scheduling/schema.ts
//
// Input checks and labels for sections and professor loading (step 8). The
// database enforces the real rules (gates, clashes, program and college);
// these checks give the Secretary a clear message before the request is sent.
//
// Section input, as typed in the form:
//   programId   programs.id
//   yearLevel   whole number, 1 to MAX_YEAR
//   (no name: the database names a new section with the next letter, A, B, C ...)
//   capacity    seats for automatic placement, 1 to MAX_CAPACITY
//
// Loading input (one subject of one section):
//   professorId, roomId   optional
//   dayOfWeek             1 (Monday) to 7 (Sunday), with startTime and endTime or none of the three
//   startTime, endTime    HH:MM, end after start

export { MAX_REASON, UUID, parseReason, type Parsed } from '@/lib/validate';
export { windowLabel } from '@/lib/format';
import { UUID, normalizeTime, text, type Parsed } from '@/lib/validate';

export const MAX_NAME = 50;
export const MAX_YEAR = 6;
export const MAX_CAPACITY = 500;

export type Meeting = 'lecture' | 'laboratory';

// "COMP 104" for the lecture, "COMP 104 Lab" for the laboratory, as on the COR.
export function subjectName(code: string, meeting: Meeting): string {
  return meeting === 'laboratory' ? `${code} Lab` : code;
}

export type ScheduleStatus = 'draft' | 'pending_dean' | 'dean_signed' | 'approved';

export const STATUS_LABEL: Record<ScheduleStatus, string> = {
  draft: 'Draft',
  pending_dean: 'Waiting for Dean',
  dean_signed: 'Waiting for Registrar',
  approved: 'Approved',
};

export const DAY_LABEL: Record<number, string> = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

export type SectionInput = {
  programId: string;
  yearLevel: number;
  capacity: number;
};

export type LoadingInput = {
  sectionSubjectId: string;
  professorId: string | null;
  roomId: string | null;
  dayOfWeek: number | null;
  startTime: string | null;
  endTime: string | null;
};

function optionalId(raw: Record<string, unknown>, key: string): string | null | undefined {
  const value = raw[key];
  if (value === null || value === undefined || value === '') return null;
  return typeof value === 'string' && UUID.test(value) ? value : undefined; // undefined = invalid
}

export function parseSectionInput(raw: unknown): Parsed<SectionInput> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The section details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const programId = text(body, 'programId');
  if (!UUID.test(programId)) return { ok: false, reason: 'Choose the program.' };

  const yearLevel = body.yearLevel;
  if (typeof yearLevel !== 'number' || !Number.isInteger(yearLevel) || yearLevel < 1 || yearLevel > MAX_YEAR) {
    return { ok: false, reason: `Year level must be a whole number from 1 to ${MAX_YEAR}.` };
  }

  const capacity = body.capacity;
  if (typeof capacity !== 'number' || !Number.isInteger(capacity) || capacity < 1 || capacity > MAX_CAPACITY) {
    return { ok: false, reason: `Capacity must be a whole number from 1 to ${MAX_CAPACITY}.` };
  }

  return { ok: true, value: { programId, yearLevel, capacity } };
}

// Editing a section changes its name and capacity only: the program and year
// level never change (the database refuses it).
export function parseSectionEdit(raw: unknown): Parsed<{ name: string; capacity: number }> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The section details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const name = text(body, 'name');
  if (name.length === 0) return { ok: false, reason: 'Enter the section name.' };
  if (name.length > MAX_NAME) return { ok: false, reason: `The section name is longer than ${MAX_NAME} characters.` };

  const capacity = body.capacity;
  if (typeof capacity !== 'number' || !Number.isInteger(capacity) || capacity < 1 || capacity > MAX_CAPACITY) {
    return { ok: false, reason: `Capacity must be a whole number from 1 to ${MAX_CAPACITY}.` };
  }
  return { ok: true, value: { name, capacity } };
}

export function parseLoadingInput(raw: unknown): Parsed<LoadingInput> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The loading details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const sectionSubjectId = text(body, 'sectionSubjectId');
  if (!UUID.test(sectionSubjectId)) return { ok: false, reason: 'That subject was not found.' };

  const professorId = optionalId(body, 'professorId');
  if (professorId === undefined) return { ok: false, reason: 'Choose a professor from the list.' };
  const roomId = optionalId(body, 'roomId');
  if (roomId === undefined) return { ok: false, reason: 'Choose a room from the list.' };

  const day = body.dayOfWeek;
  const start = typeof body.startTime === 'string' ? body.startTime.trim() : '';
  const end = typeof body.endTime === 'string' ? body.endTime.trim() : '';
  const hasDay = day !== null && day !== undefined;
  const timeParts = [hasDay, start !== '', end !== ''].filter(Boolean).length;

  if (timeParts === 0) {
    return {
      ok: true,
      value: { sectionSubjectId, professorId, roomId, dayOfWeek: null, startTime: null, endTime: null },
    };
  }
  if (timeParts < 3) return { ok: false, reason: 'Enter the day, start time and end time together.' };

  if (typeof day !== 'number' || !Number.isInteger(day) || day < 1 || day > 7) {
    return { ok: false, reason: 'Choose a day.' };
  }
  const startTime = normalizeTime(start);
  if (!startTime) return { ok: false, reason: 'Enter the start time.' };
  const endTime = normalizeTime(end);
  if (!endTime) return { ok: false, reason: 'Enter the end time.' };
  if (endTime <= startTime) return { ok: false, reason: 'The end time must be after the start time.' };

  return { ok: true, value: { sectionSubjectId, professorId, roomId, dayOfWeek: day, startTime, endTime } };
}

// "BSIT 3A": program, year level and section letter.
export function sectionLabel(programCode: string, yearLevel: number, name: string): string {
  return `${programCode} ${yearLevel}${name}`;
}

// A subject is ready for sign-off when it has a professor, a room and a time.
export function subjectIsComplete(row: {
  professorId: string | null;
  roomId: string | null;
  dayOfWeek: number | null;
}): boolean {
  return row.professorId !== null && row.roomId !== null && row.dayOfWeek !== null;
}
