// features/assessment-slip/queries.ts
//
// Reads for the slips page and the student's slip. They run under the
// signed-in person's session, so row level security applies: the Registrar
// and Admin read every student, a student reads only their own slip.
import { createClient } from '@/lib/supabase/server';
import type { SlipData } from './schema';

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
