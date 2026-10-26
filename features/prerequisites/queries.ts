// features/prerequisites/queries.ts
//
// Reads for the Prerequisites page and for credits (step 20). Each calls a
// database function that checks the caller's role and college itself (Admin and
// the Registrar: every program, Dean and Secretary: their own college), so
// nobody reads more than they may.
import { createClient } from '@/lib/supabase/server';
import { UUID, type CreditOverview, type PendingCredit, type ProgramOption, type SubjectPrerequisites } from './schema';

export async function getPrerequisitePrograms(): Promise<ProgramOption[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('prerequisite_programs');
  return Array.isArray(data) ? (data as ProgramOption[]) : [];
}

export async function getPrerequisites(programId: string): Promise<SubjectPrerequisites[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('prerequisites_list', { p_program: programId });
  return Array.isArray(data) ? (data as SubjectPrerequisites[]) : [];
}

export async function getCreditOverview(studentId: string): Promise<CreditOverview | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc('credit_overview', { p_student: studentId });
  if (error || !data) return null;
  return data as CreditOverview;
}

export async function listPendingCredits(): Promise<PendingCredit[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('credits_pending');
  return Array.isArray(data) ? (data as PendingCredit[]) : [];
}

// What the Prerequisites page needs: the programs the person may open and the subjects of
// the chosen one. The program is in the address; one that is not on the list is ignored.
export async function loadPrerequisitesPage(searchParams: { program?: string | string[] }) {
  const programs = await getPrerequisitePrograms();
  const wanted = Array.isArray(searchParams.program) ? searchParams.program[0] : searchParams.program;
  const chosen = wanted && UUID.test(wanted) ? wanted : null;
  const programId = programs.find((program) => program.id === chosen)?.id ?? programs[0]?.id ?? null;
  const subjects = programId ? await getPrerequisites(programId) : [];
  return { programs, programId, subjects };
}
