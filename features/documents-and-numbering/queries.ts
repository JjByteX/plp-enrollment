// features/documents-and-numbering/queries.ts
//
// Reads for the Registrar's documents page. They run under the signed-in
// person's session (decision-log.md #10), so row level security applies:
// Registrar and Admin see every applicant, student and document, nobody
// else sees any.
//
// The Registrar cannot read other staff accounts, so "received by" has a
// name only when the person who did it is readable; otherwise it is null.
import { createClient } from '@/lib/supabase/server';
import {
  buildChecklist,
  checklistProgress,
  isAdmissionType,
  matchesSearch,
  openLateItems,
  type AdmissionType,
  type ChecklistProgress,
  type DocumentsFilter,
  type ReceivedDocument,
  type Requirement,
} from './schema';

export type PendingApplicant = {
  applicantId: string;
  applicantRef: string;
  fullName: string;
  email: string;
  programId: string;
  programCode: string;
  admissionType: AdmissionType;
  visitDate: string | null; // YYYY-MM-DD
  progress: ChecklistProgress;
  documents: ReceivedDocument[];
};

export type ReceivedStudent = {
  studentId: string;
  studentNumber: string;
  applicantId: string;
  applicantRef: string;
  fullName: string;
  programCode: string;
  admissionType: AdmissionType;
  receivedAt: string;
  receivedByName: string | null;
  openLateItems: string[];
};

type RawRequirement = {
  doc_type: string;
  label: string;
  applies_to: string[];
  required: boolean;
  sort_order: number;
};

type RawDocument = { doc_type: string; note: string | null; received_at: string };

// PostgREST returns an object for a one to one link and an array for one to
// many, so accept both.
function first<T>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

// Supabase returns at most 1000 rows per request. Read page by page so a long
// list is never cut off without a word.
const PAGE_SIZE = 1000;
const MAX_PAGES = 20;

export async function fetchAll<T>(run: (from: number, to: number) => PromiseLike<{ data: unknown }>): Promise<T[]> {
  const rows: T[] = [];
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { data } = await run(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
    const chunk = (data ?? []) as T[];
    rows.push(...chunk);
    if (chunk.length < PAGE_SIZE) break;
  }
  return rows;
}

// Active catalog rows, in checklist order.
export async function listRequirements(): Promise<Requirement[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('document_requirements')
    .select('doc_type, label, applies_to, required, sort_order')
    .eq('active', true)
    .order('sort_order');
  const rows = (data ?? []) as RawRequirement[];
  return rows.map((row) => ({
    docType: row.doc_type,
    label: row.label,
    appliesTo: row.applies_to.filter(isAdmissionType),
    required: row.required,
    sortOrder: row.sort_order,
  }));
}

function toDocuments(rows: RawDocument[] | null | undefined): ReceivedDocument[] {
  return (rows ?? []).map((row) => ({ docType: row.doc_type, note: row.note, receivedAt: row.received_at }));
}

type RawApplicant = {
  id: string;
  applicant_ref: string;
  program_id: string;
  admission_type: string;
  users: { full_name: string; email: string } | null;
  programs: { code: string } | null;
  visit_bookings: { visit_slots: { slot_date: string } | null } | { visit_slots: { slot_date: string } | null }[] | null;
  students: unknown;
  documents: RawDocument[] | null;
};

// Applicants who are not students yet, in the order they were admitted, with
// how many required documents each has. Search matches name, applicant ref
// and email.
export async function listPendingApplicants(
  filter: Pick<DocumentsFilter, 'q' | 'programId'>,
  requirements: Requirement[]
): Promise<PendingApplicant[]> {
  const supabase = createClient();
  const rows = await fetchAll<RawApplicant>((from, to) => {
    let query = supabase
      .from('applicants')
      .select(
        'id, applicant_ref, program_id, admission_type, users(full_name, email), programs(code), ' +
          'visit_bookings(visit_slots(slot_date)), students(id), documents(doc_type, note, received_at)'
      )
      .order('admission_date')
      .order('created_at')
      .order('id')
      .range(from, to);
    if (filter.programId) query = query.eq('program_id', filter.programId);
    return query;
  });

  const result: PendingApplicant[] = [];
  for (const row of rows) {
    if (first(row.students as { id: string } | { id: string }[] | null) !== null) continue;
    if (!isAdmissionType(row.admission_type)) continue;

    const fullName = row.users?.full_name ?? '';
    const email = row.users?.email ?? '';
    if (!matchesSearch(filter.q, fullName, row.applicant_ref, email)) continue;

    const documents = toDocuments(row.documents);
    result.push({
      applicantId: row.id,
      applicantRef: row.applicant_ref,
      fullName,
      email,
      programId: row.program_id,
      programCode: row.programs?.code ?? '',
      admissionType: row.admission_type,
      visitDate: first(row.visit_bookings)?.visit_slots?.slot_date ?? null,
      progress: checklistProgress(buildChecklist(row.admission_type, requirements, documents)),
      documents,
    });
  }
  return result;
}

type RawStudent = {
  id: string;
  student_number: string;
  applicant_id: string;
  documents_received_at: string;
  users: { full_name: string } | null;
  applicants: {
    applicant_ref: string;
    program_id: string;
    admission_type: string;
    users: { full_name: string } | null;
    programs: { code: string } | null;
    documents: RawDocument[] | null;
  } | null;
};

// Students, newest first, with the late items (Form 137) still open. Read only.
export async function listReceivedStudents(
  filter: Pick<DocumentsFilter, 'q' | 'programId'>,
  requirements: Requirement[]
): Promise<ReceivedStudent[]> {
  const supabase = createClient();
  const rows = await fetchAll<RawStudent>((from, to) =>
    supabase
      .from('students')
      .select(
        'id, student_number, applicant_id, documents_received_at, users(full_name), ' +
          'applicants(applicant_ref, program_id, admission_type, users(full_name), programs(code), documents(doc_type, note, received_at))'
      )
      .order('documents_received_at', { ascending: false })
      .order('id')
      .range(from, to)
  );

  const result: ReceivedStudent[] = [];
  for (const row of rows) {
    const applicant = row.applicants;
    if (!applicant || !isAdmissionType(applicant.admission_type)) continue;
    if (filter.programId && applicant.program_id !== filter.programId) continue;

    const fullName = applicant.users?.full_name ?? '';
    if (!matchesSearch(filter.q, fullName, applicant.applicant_ref, row.student_number)) continue;

    const items = buildChecklist(applicant.admission_type, requirements, toDocuments(applicant.documents));
    result.push({
      studentId: row.id,
      studentNumber: row.student_number,
      applicantId: row.applicant_id,
      applicantRef: applicant.applicant_ref,
      fullName,
      programCode: applicant.programs?.code ?? '',
      admissionType: applicant.admission_type,
      receivedAt: row.documents_received_at,
      receivedByName: row.users?.full_name ?? null,
      openLateItems: openLateItems(items),
    });
  }
  return result;
}
