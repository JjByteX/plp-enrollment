'use server';

// features/irregular-loads/actions.ts
//
// Actions for building one student's load (step 22). Each checks the caller's role, then calls a
// database function that checks it again and applies the rules for every role, Admin included:
// a prerequisite that is not passed, a subject already passed, a subject not offered this term,
// a full section, a clash in time, and a slip that was already issued. Messages the database
// raises on purpose (P0001) are shown as written. Placing a student without a section uses the
// existing placement action in features/section-scheduling.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failure } from '@/lib/failure';
import { getCurrentUser } from '@/lib/auth/session';
import type { Role } from '@/lib/auth/roles';
import { getStudentLoad } from './queries';
import { UUID, parseAddInput, type StudentLoad } from './schema';

export type LoadActionResult = { ok: true; message: string } | { error: string };

const COLLEGE_STAFF: readonly Role[] = ['college_secretary', 'dean', 'admin'];

// The Schedules pages show the section counts and the review list; a student sees a new line on
// the next step card, which is read on every load.
const PAGES = ['/secretary/schedule', '/registrar/schedules', '/dean', '/secretary'];

async function allowed(): Promise<boolean> {
  const actor = await getCurrentUser();
  return actor !== null && COLLEGE_STAFF.includes(actor.role);
}

function refresh() {
  for (const page of PAGES) revalidatePath(page);
}

// One student's load and every subject of the program by where the student stands. Reads only.
export async function loadStudentLoad(studentId: string): Promise<StudentLoad | { error: string }> {
  if (!(await allowed())) return { error: 'Only the College Secretary or the Dean can read a student\'s load.' };
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { error: 'That student was not found.' };
  return getStudentLoad(studentId);
}

export async function addSubjectToLoad(input: unknown): Promise<LoadActionResult> {
  if (!(await allowed())) return { error: 'Only the College Secretary or the Dean can change a student\'s load.' };
  const parsed = parseAddInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('add_subject_to_load', {
    p_student: parsed.value.studentId,
    p_section: parsed.value.sectionId,
    p_subject: parsed.value.subjectId,
  });
  if (error) return failure(error, 'The subject could not be added.');

  refresh();
  return { ok: true, message: 'Subject added. The student is told.' };
}

export async function removeSubjectFromLoad(studentId: string, subjectId: string): Promise<LoadActionResult> {
  if (!(await allowed())) return { error: 'Only the College Secretary or the Dean can change a student\'s load.' };
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { error: 'That student was not found.' };
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { error: 'That subject was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('remove_subject_from_load', { p_student: studentId, p_subject: subjectId });
  if (error) return failure(error, 'The subject could not be removed.');

  refresh();
  return { ok: true, message: 'Subject removed. The student is told.' };
}
