// features/assessment-slip/queries.ts
//
// Reads for the slips page and the student's slip. They run under the
// signed-in person's session, so row level security applies: the Registrar
// and Admin read every student, a student reads only their own slip.
import { createClient } from '@/lib/supabase/server';
import { UUID, type SlipData } from './schema';

export type ReadyStudent = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  programCode: string;
  section: string;
};

// PostgREST returns an array for one to many and an object (or null) for one
// to one, so accept both.
export function first<T>(value: unknown): T | null {
  if (Array.isArray(value)) return (value[0] as T | undefined) ?? null;
  return (value as T | null) ?? null;
}

type RawReady = {
  student_id: string;
  student_number: string;
  full_name: string;
  program_code: string;
  section: string;
};

// The rows of slip_ready_students / cor_ready_students (step 18): the same
// definition "Issue all" uses, so a list and its button never disagree.
export function toReadyStudents(data: unknown): ReadyStudent[] {
  return ((data ?? []) as RawReady[]).map((row) => ({
    studentId: row.student_id,
    studentNumber: row.student_number,
    fullName: row.full_name,
    programCode: row.program_code,
    section: row.section,
  }));
}

// Students placed in a section whose schedule is approved and who have no slip
// for their current term yet, lowest student number first (the order "Issue
// all" uses).
export async function listReadyStudents(): Promise<ReadyStudent[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('slip_ready_students');
  return toReadyStudents(data);
}

// The signed-in student's own id (row level security shows a student only
// their own row), or null for anyone else. The COR reads use it too.
export async function getMyStudentId(): Promise<string | null> {
  const supabase = createClient();
  const { data: student } = await supabase.from('students').select('id').maybeSingle();
  return (student as { id: string } | null)?.id ?? null;
}

// The signed-in student's own slip, or null when none was issued.
export async function getMySlip(): Promise<SlipData | null> {
  const id = await getMyStudentId();
  if (!id) return null;
  const supabase = createClient();

  const { data } = await supabase.rpc('assessment_slip', { p_student: id });
  return (data as SlipData | null) ?? null;
}

// ---------------------------------------------------------------------------
// Registrar print and reprint (no schema change: the Registrar and Admin read
// the issued rows and call the same database functions the student does).
// ---------------------------------------------------------------------------

const MAX_PRINT = 200; // one print job and one URL stay a sensible size

type Rel<T> = T | T[] | null;
type IssuedStudent = {
  student_number: string;
  applicants: Rel<{
    users: Rel<{ full_name: string }>;
    programs: Rel<{ code: string }>;
  }>;
  student_sections: {
    school_year: string;
    semester: string;
    sections: Rel<{ year_level: number; name: string }>;
  }[];
};
type IssuedRow = { student_id: string; students: Rel<IssuedStudent> };

// Students whose slip or COR is already issued for the current term, lowest
// student number first. These are the rows the Registrar can reprint.
export async function listIssuedStudents(table: 'cors' | 'assessment_slips'): Promise<ReadyStudent[]> {
  const supabase = createClient();
  const { data: term } = await supabase.from('enrollment_term').select('school_year, semester').maybeSingle();
  if (!term) return [];

  const { data } = await supabase
    .from(table)
    .select(
      'student_id, students(student_number, applicants(users(full_name), programs(code)), student_sections(school_year, semester, sections(year_level, name)))'
    )
    .eq('school_year', term.school_year)
    .eq('semester', term.semester)
    .limit(1000);

  const rows: ReadyStudent[] = [];
  for (const row of (data ?? []) as unknown as IssuedRow[]) {
    const student = first<IssuedStudent>(row.students);
    if (!student) continue;
    const applicant = first<{ users: Rel<{ full_name: string }>; programs: Rel<{ code: string }> }>(student.applicants);
    const code = first<{ code: string }>(applicant?.programs)?.code ?? '';
    const enrollment = student.student_sections?.find(
      (s) => s.school_year === term.school_year && s.semester === term.semester
    );
    const section = first<{ year_level: number; name: string }>(enrollment?.sections);
    rows.push({
      studentId: row.student_id,
      studentNumber: student.student_number,
      fullName: first<{ full_name: string }>(applicant?.users)?.full_name ?? '',
      programCode: code,
      section: section ? `${code} ${section.year_level}${section.name}` : code,
    });
  }
  return rows.sort((a, b) => a.studentNumber.localeCompare(b.studentNumber));
}

// The ?ids= list of a registrar print page: valid student ids only, no
// repeats, in the order given, capped at one print job.
export function parsePrintIds(raw: string | string[] | undefined): { ids: string[]; capped: boolean } {
  const text = Array.isArray(raw) ? raw.join(',') : (raw ?? '');
  const all = Array.from(new Set(text.split(',').map((id) => id.trim()).filter((id) => UUID.test(id))));
  return { ids: all.slice(0, MAX_PRINT), capped: all.length > MAX_PRINT };
}

// Each student's slip, in the order of the ids. A student without an issued
// slip is left out. The database function checks that the caller is staff.
export async function getSlipsForStudents(ids: string[]): Promise<SlipData[]> {
  const supabase = createClient();
  const slips = await Promise.all(
    ids.map(async (id) => ((await supabase.rpc('assessment_slip', { p_student: id })).data as SlipData | null) ?? null)
  );
  return slips.filter((slip): slip is SlipData => slip !== null);
}
