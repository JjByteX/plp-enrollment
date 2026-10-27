// features/leave-of-absence/schema.ts
//
// Types and input checks for leave of absence and readmission (step 23). No server imports, so
// client components can use it. The database decides everything (who may record and approve,
// the one open leave, the caps, the term rules); these helpers only word it and check the input
// before it is sent.
//
// A leave is 1 or 2 regular terms (one academic year at most), 4 regular terms in all, and starts
// at the 1st or 2nd semester of a school year.
import { UUID, asObject, parseReason, type Parsed } from '@/lib/validate';

export { MAX_REASON, UUID, parseReason } from '@/lib/validate';

export const MAX_LEAVE_TERMS = 2;
export const MAX_LEAVE_TERMS_TOTAL = 4;

export type LeaveStatus = 'requested' | 'approved' | 'active' | 'ended' | 'rejected';

export const LEAVE_STATUS_LABEL: Record<LeaveStatus, string> = {
  requested: 'Waiting for the Dean',
  approved: 'Approved, not started',
  active: 'On leave',
  ended: 'Leave ended, not yet returned',
  rejected: 'Not approved',
};

export type Leave = {
  id: string;
  status: LeaveStatus;
  startYear: string;
  startSemester: '1st' | '2nd';
  terms: number;
  returnYear: string;
  returnSemester: '1st' | '2nd';
  reason: string;
  decisionNote: string | null;
  returned: boolean;
};

export type LeaveOverview = {
  term: { schoolYear: string; semester: string } | null;
  used: number; // regular terms of approved leave already used or held
  hasEnrollment: boolean;
  open: boolean; // a leave is requested, approved, running, or ended and not yet returned
  leaves: Leave[];
};

export type LeaveRequest = Leave & {
  studentNumber: string;
  fullName: string;
  programCode: string;
  usedTerms: number;
  recordedBy: string | null;
  recordedAt: string;
};

export type OnLeaveStudent = Leave & {
  studentNumber: string;
  fullName: string;
  programCode: string;
  approvedBy: string | null;
};

export type Readmission = {
  studentNumber: string;
  fullName: string;
  programCode: string;
  programName: string;
  section: string | null;
  startYear: string;
  startSemester: string;
  terms: number;
  returnYear: string;
  returnSemester: string;
  returnedYear: string;
  returnedSemester: string;
  returnedAt: string;
  approvedBy: string | null;
  readmittedBy: string | null;
};

export type LeaveTerm = { schoolYear: string; semester: '1st' | '2nd' };

// "1st semester of SY 2026-2027"
export function leaveTermText(schoolYear: string, semester: string): string {
  return `${semester === 'summer' ? 'Summer' : `${semester} semester`}, SY ${schoolYear}`;
}

export function leaveTermKey(term: LeaveTerm): string {
  return `${term.schoolYear}|${term.semester}`;
}

function nextRegular(term: LeaveTerm): LeaveTerm {
  if (term.semester === '1st') return { schoolYear: term.schoolYear, semester: '2nd' };
  const start = Number.parseInt(term.schoolYear.slice(0, 4), 10);
  return { schoolYear: `${start + 1}-${start + 2}`, semester: '1st' };
}

// The first terms a leave may start at: the current term when it is a regular term, then the next
// regular terms. The database refuses one the student is already placed in.
export function startOptions(current: { schoolYear: string; semester: string } | null, count = 5): LeaveTerm[] {
  if (!current || !/^\d{4}-\d{4}$/.test(current.schoolYear)) return [];
  let term: LeaveTerm =
    current.semester === '1st' || current.semester === '2nd'
      ? { schoolYear: current.schoolYear, semester: current.semester }
      : nextRegular({ schoolYear: current.schoolYear, semester: '2nd' });
  const options: LeaveTerm[] = [];
  for (let index = 0; index < count; index += 1) {
    options.push(term);
    term = nextRegular(term);
  }
  return options;
}

export type RecordInput = { studentId: string; schoolYear: string; semester: '1st' | '2nd'; terms: number; reason: string };

export function parseRecordInput(raw: unknown): Parsed<RecordInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The leave is missing.' };
  const { studentId, schoolYear, semester, terms } = body;
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { ok: false, reason: 'That student was not found.' };
  if (typeof schoolYear !== 'string' || !/^\d{4}-\d{4}$/.test(schoolYear) || (semester !== '1st' && semester !== '2nd')) {
    return { ok: false, reason: 'Choose the first term of the leave.' };
  }
  if (terms !== 1 && terms !== 2) return { ok: false, reason: 'Choose how many terms the leave lasts.' };
  const reason = parseReason(body.reason);
  if (!reason.ok) return reason;
  return { ok: true, value: { studentId, schoolYear, semester, terms, reason: reason.value } };
}
