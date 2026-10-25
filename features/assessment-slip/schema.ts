// features/assessment-slip/schema.ts
//
// What the assessment slip shows (step 9). The database builds it in
// assessment_slip(); this is its shape and the wording of its dates.

export { UUID } from '@/features/visit-scheduling/schema';
export { DAY_LABEL, subjectName, windowLabel } from '@/features/section-scheduling/schema';
import type { Meeting } from '@/features/section-scheduling/schema';

export type SlipSubject = {
  code: string;
  title: string;
  meeting: Meeting;
  units: number; // 0 on a laboratory row: units count once
  professor: string | null;
  room: string | null;
  day: number | null;
  start: string | null; // HH:MM
  end: string | null; // HH:MM
};

export type SlipData = {
  studentNumber: string;
  fullName: string;
  programCode: string;
  programName: string;
  section: string;
  issuedAt: string;
  paymentRequired: boolean;
  subjects: SlipSubject[];
};

// "Oct 25, 2026" in Manila time, so the server and the browser print the same text.
export function formatIssuedDate(value: string): string {
  return new Intl.DateTimeFormat('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeZone: 'Asia/Manila',
  }).format(new Date(value));
}

export function totalUnits(subjects: SlipSubject[]): number {
  return subjects.reduce((sum, subject) => sum + Number(subject.units), 0);
}
