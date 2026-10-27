// features/irregular-loads/schema.ts
//
// Types and small helpers for building one student's load (step 22). No server imports, so
// client components can use it. The database decides everything (who may change a load, which
// subjects are blocked, seats, time clashes, the locked slip); these helpers only word it.
//
// A load is the subject list of one enrollment (one student in one term). A regular student's
// list is copied from their section. The Secretary or the Dean adds a retake or a back subject
// from any section of the current term that offers it.
import { UUID, asObject, type Parsed } from '@/lib/validate';

export { UUID } from '@/lib/validate';

export type LoadStatus = 'in_load' | 'passed' | 'blocked' | 'not_offered' | 'allowed';

export type BlockingPrerequisite = { code: string; status: string };

export type SectionOption = { sectionId: string; label: string; taken: number; capacity: number };

export type LoadSubject = {
  subjectId: string;
  code: string;
  title: string;
  yearLevel: number;
  semester: string;
  status: LoadStatus;
  source: 'section' | 'added' | null; // only for a subject in the load
  takenIn: string | null; // the section a subject in the load is taken in
  blockedBy: BlockingPrerequisite[];
  options: SectionOption[]; // the sections of this term that offer the subject
};

export type StudentLoad = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  programCode: string;
  schoolYear: string;
  semester: string;
  enrolled: boolean; // false until the student has a section in the current term
  section: string | null;
  locked: boolean; // the assessment slip was issued, so the load is fixed
  places: SectionOption[]; // the sections a student without a section can be placed in
  subjects: LoadSubject[];
};

// The student the Needs review list opens.
export type LoadStudent = { studentId: string; studentNumber: string; fullName: string };

export const BLOCK_STATUS_LABEL: Record<string, string> = {
  incomplete: 'incomplete',
  failed: 'failed',
  dropped: 'dropped',
  not_taken: 'not taken',
};

export function blockedText(subject: LoadSubject): string {
  const parts = subject.blockedBy.map((item) => `${item.code} (${BLOCK_STATUS_LABEL[item.status] ?? item.status.replace(/_/g, ' ')})`);
  return parts.length === 0 ? 'A prerequisite is not passed.' : `Needs a passed prerequisite: ${parts.join(', ')}.`;
}

// A seat label for one section option, for example "BSIT 1A (12 of 40)".
export function optionLabel(option: SectionOption): string {
  return `${option.label} (${option.taken} of ${option.capacity})`;
}

export function optionFull(option: SectionOption): boolean {
  return option.taken >= option.capacity;
}

export type AddInput = { studentId: string; sectionId: string; subjectId: string };

export function parseAddInput(raw: unknown): Parsed<AddInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The subject is missing.' };
  const { studentId, sectionId, subjectId } = body;
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { ok: false, reason: 'That student was not found.' };
  if (typeof sectionId !== 'string' || !UUID.test(sectionId)) return { ok: false, reason: 'Choose a section.' };
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { ok: false, reason: 'That subject was not found.' };
  return { ok: true, value: { studentId, sectionId, subjectId } };
}
