// features/cor/schema.ts
//
// What the Certificate of Registration shows (step 11). The database builds it
// in certificate_of_registration(); this is its shape and the wording of its
// term and year level. No server imports, so client components can use it.

export { UUID, formatIssuedDate, scheduleText, subjectName, totalUnits } from '@/features/assessment-slip/schema';
export { ADMISSION_TYPE_LABEL } from '@/features/documents-and-numbering/schema';
export type { SlipSubject } from '@/features/assessment-slip/schema';
import type { SlipSubject } from '@/features/assessment-slip/schema';
import type { AdmissionType } from '@/features/documents-and-numbering/schema';

export type Semester = '1st' | '2nd' | 'summer';

export const SEMESTER_LABEL: Record<Semester, string> = {
  '1st': '1st Semester',
  '2nd': '2nd Semester',
  summer: 'Summer',
};

const YEAR_LABEL: Record<number, string> = {
  1: 'First Year',
  2: 'Second Year',
  3: 'Third Year',
  4: 'Fourth Year',
  5: 'Fifth Year',
  6: 'Sixth Year',
};

export function yearLabel(yearLevel: number): string {
  return YEAR_LABEL[yearLevel] ?? `Year ${yearLevel}`;
}

// "1st Semester, SY 2026-2027"
export function termLabel(schoolYear: string, semester: string): string {
  const label = SEMESTER_LABEL[semester as Semester] ?? semester;
  return `${label}, SY ${schoolYear}`;
}

export type CorData = {
  studentNumber: string;
  fullName: string;
  programCode: string;
  programName: string;
  collegeName: string;
  section: string;
  yearLevel: number;
  admissionType: AdmissionType;
  schoolYear: string;
  semester: Semester;
  issuedAt: string;
  issuedByName: string;
  issuedByRole: string;
  paymentRequired: boolean;
  amountDue: number | null; // null unless payment was required and cleared
  amountPaid: number | null;
  receiptNo: string | null;
  subjects: SlipSubject[];
};
