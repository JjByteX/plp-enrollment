// features/prerequisites/schema.ts
//
// Types and input checks for prerequisites and credits (step 20). No server
// imports, so client components can use it. The database enforces the real
// rules (who may set prerequisites, same program, earlier in the curriculum,
// no loop; who may record and approve a credit); these checks give a clear
// message before the request is sent.
//
// Prerequisites:  a subject and the ids of the earlier subjects of the same program
//                 that must be passed first. All of them are required.
// Credit input:   a student, a subject of the student's program, and the reason, which
//                 names the line of the transferee's TOR (1 to 500 characters).
import type { Role } from '@/lib/auth/roles';
import { UUID, asObject, parseReason, type Parsed } from '@/lib/validate';

export { MAX_REASON, UUID, parseReason } from '@/lib/validate';

export type ProgramOption = { id: string; code: string; name: string };

export type SubjectRef = { subjectId: string; code: string; title: string };

export type SubjectPrerequisites = SubjectRef & {
  yearLevel: number | null;
  semester: string;
  prerequisites: SubjectRef[];
};

const SEMESTER_RANK: Record<string, number> = { '1st': 1, '2nd': 2, summer: 3 };

// Admin and the Dean of the college set prerequisites. The Registrar and the Secretary only view.
export function canEditPrerequisites(role: Role): boolean {
  return role === 'admin' || role === 'dean';
}

// The same rule the database uses: a prerequisite comes earlier in the curriculum, which is
// a lower year level, or the same year level and an earlier semester.
export function isEarlier(candidate: SubjectPrerequisites, subject: SubjectPrerequisites): boolean {
  if (candidate.yearLevel === null || subject.yearLevel === null) return false;
  if (candidate.yearLevel !== subject.yearLevel) return candidate.yearLevel < subject.yearLevel;
  return (SEMESTER_RANK[candidate.semester] ?? 0) < (SEMESTER_RANK[subject.semester] ?? 0);
}

export function earlierSubjects(all: SubjectPrerequisites[], subject: SubjectPrerequisites): SubjectPrerequisites[] {
  return all.filter((candidate) => candidate.subjectId !== subject.subjectId && isEarlier(candidate, subject));
}

export function prerequisiteText(subject: SubjectPrerequisites): string {
  return subject.prerequisites.length === 0 ? 'None' : subject.prerequisites.map((item) => item.code).join(', ');
}

export type PrerequisiteInput = { subjectId: string; requiredIds: string[] };

export function parsePrerequisiteInput(raw: unknown): Parsed<PrerequisiteInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The prerequisites are missing.' };
  const subjectId = body.subjectId;
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { ok: false, reason: 'That subject was not found.' };
  const required = body.requiredIds;
  if (!Array.isArray(required) || required.some((id) => typeof id !== 'string' || !UUID.test(id))) {
    return { ok: false, reason: 'A required subject was not found.' };
  }
  if (required.includes(subjectId)) return { ok: false, reason: 'A subject cannot require itself.' };
  return { ok: true, value: { subjectId, requiredIds: [...new Set(required as string[])] } };
}

export type CreditStatus = 'pending' | 'approved' | 'rejected';
export const CREDIT_STATUS_LABEL: Record<CreditStatus, string> = {
  pending: 'Waiting for the Registrar',
  approved: 'Approved',
  rejected: 'Rejected',
};

export type StudentCredit = {
  id: string;
  status: CreditStatus;
  code: string;
  title: string;
  reason: string;
  rejectedReason: string | null;
  recordedBy: string | null;
  recordedAt: string;
};

export type CreditOption = { subjectId: string; code: string; title: string; yearLevel: number | null };

export type CreditOverview = { credits: StudentCredit[]; options: CreditOption[] };

export type PendingCredit = {
  id: string;
  studentNumber: string;
  fullName: string;
  program: string;
  code: string;
  title: string;
  reason: string;
  recordedBy: string | null;
  recordedAt: string;
};

export type CreditInput = { studentId: string; subjectId: string; reason: string };

export function parseCreditInput(raw: unknown): Parsed<CreditInput> {
  const body = asObject(raw);
  if (!body) return { ok: false, reason: 'The credit is missing.' };
  const studentId = body.studentId;
  const subjectId = body.subjectId;
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { ok: false, reason: 'That student was not found.' };
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { ok: false, reason: 'Choose the subject to credit.' };
  const reason = parseReason(body.reason);
  if (!reason.ok) return reason;
  return { ok: true, value: { studentId, subjectId, reason: reason.value } };
}
