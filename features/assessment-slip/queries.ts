// features/assessment-slip/queries.ts
//
// Reads for the slips page and the student's slip. They run under the
// signed-in person's session, so row level security applies: the Registrar
// and Admin read every student, a student reads only their own slip.
import { createClient } from '@/lib/supabase/server';
import { sectionLabel } from '@/features/section-scheduling/schema';
import type { SlipData } from './schema';

export type ReadyStudent = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  programCode: string;
  section: string;
};

type RawStudent = {
  id: string;
  student_number: string;
  applicants: { programs: { code: string } | null; users: { full_name: string } | null } | null;
  student_sections: unknown;
  assessment_slips: unknown;
};

type RawPlacement = { sections: { name: string; year_level: number; schedule_status: string } | null };

// PostgREST returns an array for one to many and an object (or null) for one
// to one, so accept both.
export function first<T>(value: unknown): T | null {
  if (Array.isArray(value)) return (value[0] as T | undefined) ?? null;
  return (value as T | null) ?? null;
}

// Students placed in a section whose schedule is approved and who have no slip
// yet, lowest student number first (the order "Issue all" uses).
export async function listReadyStudents(): Promise<ReadyStudent[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('students')
    .select(
      'id, student_number, applicants(programs(code), users(full_name)), ' +
        'student_sections(sections(name, year_level, schedule_status)), assessment_slips(id)'
    )
    .order('student_number');

  return ((data ?? []) as unknown as RawStudent[]).flatMap((row) => {
    const section = first<RawPlacement>(row.student_sections)?.sections ?? null;
    if (!section || section.schedule_status !== 'approved' || first(row.assessment_slips)) return [];
    const code = row.applicants?.programs?.code ?? '';
    return [
      {
        studentId: row.id,
        studentNumber: row.student_number,
        fullName: row.applicants?.users?.full_name ?? '',
        programCode: code,
        section: sectionLabel(code, section.year_level, section.name),
      },
    ];
  });
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
