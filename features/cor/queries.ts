// features/cor/queries.ts
//
// Reads for the COR page and the student's COR. They run under the signed-in
// person's session, so row level security applies: the Registrar and Admin
// read every student, a student reads only their own COR.
import { createClient } from '@/lib/supabase/server';
import { sectionLabel } from '@/features/section-scheduling/schema';
import { first, getMyStudentId } from '@/features/assessment-slip/queries';
import type { ReadyStudent } from '@/features/assessment-slip/queries';
import type { CorData } from './schema';

type RawStudent = {
  id: string;
  student_number: string;
  applicants: { withdrawn_at: string | null; programs: { code: string } | null; users: { full_name: string } | null } | null;
  student_sections: unknown;
  assessment_slips: unknown;
  payments: unknown;
  cors: unknown;
};

type RawPlacement = { sections: { name: string; year_level: number } | null };

// Students whose slip is issued, whose payment is cleared (or was never
// required) and who have no COR yet, lowest student number first (the order
// "Issue all" uses). Same row shape as the slips page. A student who withdrew
// (step 17) is not listed.
export async function listReadyForCor(): Promise<ReadyStudent[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('students')
    .select(
      'id, student_number, applicants(withdrawn_at, programs(code), users(full_name)), ' +
        'student_sections(sections(name, year_level)), assessment_slips(payment_required), payments(status), cors(id)'
    )
    .order('student_number');

  return ((data ?? []) as unknown as RawStudent[]).flatMap((row) => {
    const slip = first<{ payment_required: boolean }>(row.assessment_slips);
    if (!slip || first(row.cors)) return [];
    if (row.applicants?.withdrawn_at) return [];
    if (slip.payment_required && first<{ status: string }>(row.payments)?.status !== 'cleared') return [];

    const section = first<RawPlacement>(row.student_sections)?.sections ?? null;
    const code = row.applicants?.programs?.code ?? '';
    return [
      {
        studentId: row.id,
        studentNumber: row.student_number,
        fullName: row.applicants?.users?.full_name ?? '',
        programCode: code,
        section: section ? sectionLabel(code, section.year_level, section.name) : '',
      },
    ];
  });
}

// The signed-in student's own COR, or null when none was issued.
export async function getMyCor(): Promise<CorData | null> {
  const id = await getMyStudentId();
  if (!id) return null;

  const supabase = createClient();
  const { data } = await supabase.rpc('certificate_of_registration', { p_student: id });
  return (data as CorData | null) ?? null;
}
