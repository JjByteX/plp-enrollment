// features/irregular-loads/queries.ts
//
// The read for one student's load (step 22). It calls a database function that checks the
// caller's role and college itself (the Secretary and the Dean see students of their own
// college, Admin all), so nobody reads more than they may.
import { createClient } from '@/lib/supabase/server';
import type { StudentLoad } from './schema';

export async function getStudentLoad(studentId: string): Promise<StudentLoad | { error: string }> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc('student_load', { p_student: studentId });
  if (error) return { error: error.code === 'P0001' ? error.message : 'The load could not be read.' };
  if (!data) return { error: 'The load could not be read.' };
  return data as StudentLoad;
}
