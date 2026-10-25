'use server';

// features/section-scheduling/actions.ts
//
// Actions for sections, professor loading, the sign-off chain and student
// placement. Every action checks the caller first, then runs under the
// caller's own session so row level security applies and the audit log
// records who did it (decision-log.md #10). The database enforces the chain
// (Secretary prepares, Dean signs off, Registrar approves) and the clash
// rules; the messages it raises on purpose (P0001) are shown as written.
// Rejecting and moving go through database functions so the reason and the
// notification are in the same transaction as the change.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import type { Role } from '@/lib/auth/roles';
import { getSectionDetail, type SectionDetail } from './queries';
import {
  MAX_REASON,
  UUID,
  parseLoadingInput,
  parseReason,
  parseSectionEdit,
  parseSectionInput,
  type LoadingInput,
  type SectionInput,
} from './schema';

export type ScheduleActionResult = { ok: true; message: string } | { error: string };

const PAGES = ['/secretary/schedule', '/registrar/schedules'];

async function requireRole(roles: readonly Role[]): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && roles.includes(actor.role) ? actor : null;
}

const COLLEGE_STAFF: readonly Role[] = ['college_secretary', 'dean', 'admin'];
const DEAN: readonly Role[] = ['dean', 'admin'];
const REGISTRAR: readonly Role[] = ['registrar', 'admin'];

function refresh() {
  for (const page of PAGES) revalidatePath(page);
}

function failure(error: { code?: string; message: string }, fallback: string): { error: string } {
  if (error.code === 'P0001') return { error: error.message };
  if (error.code === '23P01') {
    return { error: 'That professor or room is already used at that time in another section.' };
  }
  if (error.code === '23505') {
    return { error: 'A section with this name already exists for this program and year level.' };
  }
  return { error: fallback };
}

// The rows a section and its students show when it is opened. Reads only.
export async function loadSectionDetail(sectionId: string): Promise<SectionDetail | { error: string }> {
  const actor = await getCurrentUser();
  if (!actor) return { error: 'Sign in again to continue.' };
  if (!UUID.test(sectionId)) return { error: 'That section was not found.' };
  return getSectionDetail(sectionId);
}

export async function createSection(input: SectionInput): Promise<ScheduleActionResult> {
  const actor = await requireRole(COLLEGE_STAFF);
  if (!actor) return { error: 'Only the College Secretary or the Dean can create sections.' };

  const parsed = parseSectionInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { programId, yearLevel, name, capacity } = parsed.value;

  const supabase = createClient();
  const { error } = await supabase
    .from('sections')
    .insert({ program_id: programId, year_level: yearLevel, name, capacity });
  if (error) return failure(error, 'The section could not be saved.');

  refresh();
  return { ok: true, message: 'Section created. Its subjects were added and waiting students were placed.' };
}

// Name and capacity only: the program and year level of a section never change.
export async function updateSection(
  sectionId: string,
  input: { name: string; capacity: number }
): Promise<ScheduleActionResult> {
  const actor = await requireRole(COLLEGE_STAFF);
  if (!actor) return { error: 'Only the College Secretary or the Dean can edit sections.' };
  if (!UUID.test(sectionId)) return { error: 'That section was not found.' };

  const parsed = parseSectionEdit(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { data, error } = await supabase
    .from('sections')
    .update({ name: parsed.value.name, capacity: parsed.value.capacity })
    .eq('id', sectionId)
    .select('id');
  if (error) return failure(error, 'The section could not be saved.');
  if (!data || data.length === 0) return { error: 'That section was not found.' };

  refresh();
  return { ok: true, message: 'Section saved.' };
}

// One subject of a section: professor, room, day and time. Locked by the
// database once the schedule is submitted.
export async function saveLoading(input: LoadingInput): Promise<ScheduleActionResult> {
  const actor = await requireRole(COLLEGE_STAFF);
  if (!actor) return { error: 'Only the College Secretary or the Dean can assign professors and rooms.' };

  const parsed = parseLoadingInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { sectionSubjectId, professorId, roomId, dayOfWeek, startTime, endTime } = parsed.value;

  const supabase = createClient();
  const { data, error } = await supabase
    .from('section_subjects')
    .update({
      professor_id: professorId,
      room_id: roomId,
      day_of_week: dayOfWeek,
      start_time: startTime,
      end_time: endTime,
    })
    .eq('id', sectionSubjectId)
    .select('id');
  if (error) return failure(error, 'The loading could not be saved.');
  if (!data || data.length === 0) return { error: 'That subject was not found.' };

  refresh();
  return { ok: true, message: 'Loading saved.' };
}

async function changeStatus(
  sectionId: string,
  status: 'pending_dean' | 'dean_signed' | 'approved',
  roles: readonly Role[],
  denied: string,
  done: string
): Promise<ScheduleActionResult> {
  const actor = await requireRole(roles);
  if (!actor) return { error: denied };
  if (!UUID.test(sectionId)) return { error: 'That section was not found.' };

  const supabase = createClient();
  const { data, error } = await supabase
    .from('sections')
    .update({ schedule_status: status })
    .eq('id', sectionId)
    .select('id');
  if (error) return failure(error, 'The schedule could not be updated.');
  if (!data || data.length === 0) return { error: 'That section was not found.' };

  refresh();
  return { ok: true, message: done };
}

export async function submitSchedule(sectionId: string): Promise<ScheduleActionResult> {
  return changeStatus(
    sectionId,
    'pending_dean',
    COLLEGE_STAFF,
    'Only the College Secretary or the Dean can submit a schedule.',
    'Submitted. The Dean can now sign off the professor loading.'
  );
}

export async function signOffSchedule(sectionId: string): Promise<ScheduleActionResult> {
  return changeStatus(
    sectionId,
    'dean_signed',
    DEAN,
    'Only the Dean can sign off professor loading.',
    'Signed off. The Registrar can now approve the schedule.'
  );
}

export async function approveSchedule(sectionId: string): Promise<ScheduleActionResult> {
  return changeStatus(
    sectionId,
    'approved',
    REGISTRAR,
    'Only the Registrar can approve a schedule.',
    'Approved. The students in this section were told.'
  );
}

// The Dean (from "Waiting for Dean") or the Registrar (from "Waiting for
// Registrar") sends the schedule back to draft with a reason. The database
// decides who may reject from which status.
export async function rejectSchedule(sectionId: string, reason: string): Promise<ScheduleActionResult> {
  const actor = await requireRole(['dean', 'registrar', 'admin']);
  if (!actor) return { error: 'Only the Dean or the Registrar can reject a schedule.' };
  if (!UUID.test(sectionId)) return { error: 'That section was not found.' };
  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('reject_schedule', { p_section: sectionId, p_reason: parsed.value });
  if (error) return failure(error, 'The schedule could not be rejected.');

  refresh();
  return { ok: true, message: 'Sent back to draft. The Secretary will see the reason.' };
}

// Put a student into a section, or move them. Allowed any time until the
// assessment slip is issued (the database refuses after that).
export async function moveStudent(
  studentId: string,
  sectionId: string,
  reason?: string
): Promise<ScheduleActionResult> {
  const actor = await requireRole(COLLEGE_STAFF);
  if (!actor) return { error: 'Only the College Secretary or the Dean can place students in sections.' };
  if (!UUID.test(studentId) || !UUID.test(sectionId)) return { error: 'Choose a student and a section.' };

  const note = (reason ?? '').trim();
  if (note.length > MAX_REASON) return { error: `The reason is longer than ${MAX_REASON} characters.` };

  const supabase = createClient();
  const { error } = await supabase.rpc('move_student_section', {
    p_student: studentId,
    p_section: sectionId,
    p_reason: note.length > 0 ? note : null,
  });
  if (error) return failure(error, 'The student could not be placed.');

  refresh();
  return { ok: true, message: 'Student placed. They will see it on their next step card.' };
}
