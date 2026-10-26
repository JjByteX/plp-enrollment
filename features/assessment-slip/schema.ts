// features/assessment-slip/schema.ts
//
// What the assessment slip shows (step 9). The database builds it in
// assessment_slip(); this is its shape and the wording of its dates.

export { UUID } from '@/features/visit-scheduling/schema';
export { DAY_LABEL, subjectName, windowLabel } from '@/features/section-scheduling/schema';
import { DAY_LABEL, windowLabel, type Meeting } from '@/features/section-scheduling/schema';

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

// "Monday, 8:00 AM to 10:00 AM", or empty when the subject has no time yet.
// The slip and the COR both print it.
export function scheduleText(day: number | null, start: string | null, end: string | null): string {
  return day !== null && start && end ? `${DAY_LABEL[day]}, ${windowLabel(start, end)}` : '';
}

export function totalUnits(subjects: SlipSubject[]): number {
  return subjects.reduce((sum, subject) => sum + Number(subject.units), 0);
}
