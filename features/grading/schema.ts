// features/grading/schema.ts
//
// Types and input checks for the grading scale and grades (step 19). No server
// imports, so client components can use it. The database enforces the real
// rules (who may enter, submit, approve and change a grade, and the scale);
// these checks give a clear message before the request is sent.
//
// Scale input:  incWindowDays (1 to 365) and bands. A band has a label (1 to 30), an outcome
//               (passed, incomplete, failed or dropped), a descriptive flag, and either both
//               a from and a to number or neither. Two numeric bands may not overlap.
// Grade entry:  one text per student, matched to a band: a number inside a numeric band, or
//               a label such as INC. Descriptive bands never match.
import { parseChoice, type Parsed } from '@/lib/validate';

export { MAX_REASON, UUID, parseReason } from '@/lib/validate';

export const OUTCOMES = ['passed', 'incomplete', 'failed', 'dropped'] as const;
export type Outcome = (typeof OUTCOMES)[number];
export const OUTCOME_LABEL: Record<Outcome, string> = {
  passed: 'Passed',
  incomplete: 'Incomplete',
  failed: 'Failed',
  dropped: 'Dropped',
};

export const MAX_BAND_LABEL = 30;
export const MAX_INC_DAYS = 365;

export type Band = { label: string; outcome: Outcome; descriptive: boolean; from: number | null; to: number | null };
export type Scale = { incWindowDays: number; bands: Band[] };

export type SheetStatus = 'not_submitted' | 'draft' | 'submitted' | 'approved';
export const STATUS_LABEL: Record<SheetStatus, string> = {
  not_submitted: 'Not submitted',
  draft: 'Not submitted',
  submitted: 'Submitted',
  approved: 'Approved',
};

export type GradeSection = {
  sectionId: string;
  subjectId: string;
  label: string; // BSIT 3A
  code: string;
  title: string;
  schoolYear: string;
  semester: string;
  status: SheetStatus;
  students: number;
  graded: number;
  professor: string | null;
};

export type SheetStudent = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  gradeId: string | null;
  gradeText: string | null;
  outcome: Outcome | null;
  lapsed: boolean;
  changePending: boolean;
};

export type Sheet = {
  sectionId: string;
  subjectId: string;
  label: string;
  code: string;
  title: string;
  schoolYear: string;
  semester: string;
  status: SheetStatus;
  returnedReason: string | null;
  students: SheetStudent[];
};

export type ChangeStatus = 'pending_dean' | 'pending_registrar';
export type GradeChange = {
  id: string;
  status: ChangeStatus;
  kind: 'correction' | 'inc_completion' | 'drop';
  label: string;
  code: string;
  title: string;
  studentNumber: string;
  fullName: string;
  oldGrade: string;
  oldOutcome: Outcome;
  newGrade: string;
  newOutcome: Outcome;
  reason: string;
  proposedBy: string | null;
  proposedAt: string;
};

export const KIND_LABEL: Record<GradeChange['kind'], string> = {
  correction: 'Correction',
  inc_completion: 'Completing an incomplete',
  drop: 'Official drop',
};

export type GradeTab = 'sections' | 'changes' | 'completed' | 'leave';

export function parseGradeTab(raw: unknown): GradeTab {
  return parseChoice(raw, ['sections', 'changes', 'completed', 'leave'], 'sections');
}

export function scaleReady(scale: Scale): boolean {
  return scale.bands.some((band) => !band.descriptive);
}

// The band a typed grade belongs to, the same rule the database uses: a number inside a
// numeric band first, then a label. Null means the grade is not on the scale.
export function matchBand(scale: Scale, typed: string): Band | null {
  const text = typed.trim();
  if (text === '') return null;
  const real = scale.bands.filter((band) => !band.descriptive);
  if (/^[0-9]{1,4}(\.[0-9]{1,2})?$/.test(text)) {
    const value = Number(text);
    const hit = real.find((band) => band.from !== null && band.to !== null && value >= band.from && value <= band.to);
    if (hit) return hit;
  }
  return real.find((band) => band.label.toLowerCase() === text.toLowerCase()) ?? null;
}

export function parseScale(raw: unknown): Parsed<Scale> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The scale is missing.' };
  }
  const body = raw as Record<string, unknown>;

  const days = body.incWindowDays;
  if (typeof days !== 'number' || !Number.isInteger(days) || days < 1 || days > MAX_INC_DAYS) {
    return { ok: false, reason: `The incomplete window must be a whole number of days from 1 to ${MAX_INC_DAYS}.` };
  }
  if (!Array.isArray(body.bands)) return { ok: false, reason: 'The bands are missing.' };

  const bands: Band[] = [];
  for (const [index, item] of body.bands.entries()) {
    const row = (typeof item === 'object' && item !== null ? item : {}) as Record<string, unknown>;
    const label = typeof row.label === 'string' ? row.label.trim() : '';
    if (label === '' || label.length > MAX_BAND_LABEL) {
      return { ok: false, reason: `Band ${index + 1} needs a label of 1 to ${MAX_BAND_LABEL} characters.` };
    }
    if (bands.some((band) => band.label.toLowerCase() === label.toLowerCase())) {
      return { ok: false, reason: `Two bands are named ${label}.` };
    }
    const descriptive = row.descriptive === true;
    const outcome = descriptive ? 'passed' : row.outcome;
    if (!OUTCOMES.includes(outcome as Outcome)) return { ok: false, reason: `Choose the outcome of ${label}.` };

    const from = typeof row.from === 'number' ? row.from : null;
    const to = typeof row.to === 'number' ? row.to : null;
    if ((from === null) !== (to === null) || (from !== null && to !== null && from > to)) {
      return { ok: false, reason: `Enter the from and to numbers of ${label}, with from not above to, or leave both empty.` };
    }
    bands.push({ label, outcome: outcome as Outcome, descriptive, from, to });
  }

  const numeric = bands.filter((band) => !band.descriptive && band.from !== null && band.to !== null);
  for (const [i, a] of numeric.entries()) {
    for (const b of numeric.slice(i + 1)) {
      if ((a.from as number) <= (b.to as number) && (b.from as number) <= (a.to as number)) {
        return { ok: false, reason: `The bands ${a.label} and ${b.label} overlap.` };
      }
    }
  }
  return { ok: true, value: { incWindowDays: days, bands } };
}

export type GradeEntry = { studentId: string; grade: string };
