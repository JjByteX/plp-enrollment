// features/cor/queries.ts
//
// Reads for the COR page and the student's COR. They run under the signed-in
// person's session, so row level security applies: the Registrar and Admin
// read every student, a student reads only their own COR.
import { createClient } from '@/lib/supabase/server';
import { getMyStudentId, toReadyStudents } from '@/features/assessment-slip/queries';
import type { ReadyStudent } from '@/features/assessment-slip/queries';
import type { CorData } from './schema';

// Students whose slip is issued for their current term, whose payment is
// cleared (or was never required) and who have no COR for it yet, lowest
// student number first (the order "Issue all" uses). Same row shape as the
// slips page. A student who withdrew (step 17) is not listed.
export async function listReadyForCor(): Promise<ReadyStudent[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('cor_ready_students');
  return toReadyStudents(data);
}

// The signed-in student's own COR, or null when none was issued.
export async function getMyCor(): Promise<CorData | null> {
  const id = await getMyStudentId();
  if (!id) return null;

  const supabase = createClient();
  const { data } = await supabase.rpc('certificate_of_registration', { p_student: id });
  return (data as CorData | null) ?? null;
}
