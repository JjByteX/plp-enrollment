'use server';

// features/leave-of-absence/actions.ts
//
// Actions for leave of absence (step 23). Each checks the caller's role, then calls a database
// function that checks it again. The Secretary or the Dean records a leave, the Dean decides it,
// and the system does the rest (deactivation, ending, readmission). Messages the database raises
// on purpose (P0001) are shown as written.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failure } from '@/lib/failure';
import { getCurrentUser } from '@/lib/auth/session';
import type { Role } from '@/lib/auth/roles';
import { getLeaveOverview } from './queries';
import { UUID, parseReason, parseRecordInput, type LeaveOverview } from './schema';

export type LeaveActionResult = { ok: true; message: string } | { error: string };

const PAGES = ['/dean/grades', '/registrar/grades', '/secretary/schedule', '/registrar/schedules'];

const RECORDERS: readonly Role[] = ['college_secretary', 'dean', 'admin'];
const DEANS: readonly Role[] = ['dean', 'admin'];

async function allowed(roles: readonly Role[]): Promise<boolean> {
  const actor = await getCurrentUser();
  return actor !== null && roles.includes(actor.role);
}

function done(message: string): LeaveActionResult {
  for (const page of PAGES) revalidatePath(page);
  return { ok: true, message };
}

// One student's leaves and how many terms are used. Reads only.
export async function loadLeaveOverview(studentId: string): Promise<LeaveOverview | { error: string }> {
  if (!(await allowed(RECORDERS))) return { error: 'Only the College Secretary or the Dean can read leaves.' };
  if (typeof studentId !== 'string' || !UUID.test(studentId)) return { error: 'That student was not found.' };
  return getLeaveOverview(studentId);
}

export async function recordLeave(input: unknown): Promise<LeaveActionResult> {
  if (!(await allowed(RECORDERS))) return { error: 'Only the College Secretary or the Dean can record a leave.' };
  const parsed = parseRecordInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('record_leave', {
    p_student: parsed.value.studentId,
    p_year: parsed.value.schoolYear,
    p_semester: parsed.value.semester,
    p_terms: parsed.value.terms,
    p_reason: parsed.value.reason,
  });
  if (error) return failure(error, 'The leave could not be recorded.');
  return done('Leave recorded. It waits for the Dean.');
}

export async function approveLeave(leaveId: string): Promise<LeaveActionResult> {
  if (!(await allowed(DEANS))) return { error: 'Only the Dean can approve a leave.' };
  if (typeof leaveId !== 'string' || !UUID.test(leaveId)) return { error: 'That leave was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('decide_leave', { p_leave: leaveId, p_approve: true, p_note: null });
  if (error) return failure(error, 'The leave could not be approved.');
  return done('Leave approved. The student is told.');
}

export async function rejectLeave(leaveId: string, reason: string): Promise<LeaveActionResult> {
  if (!(await allowed(DEANS))) return { error: 'Only the Dean can reject a leave.' };
  if (typeof leaveId !== 'string' || !UUID.test(leaveId)) return { error: 'That leave was not found.' };
  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('decide_leave', { p_leave: leaveId, p_approve: false, p_note: parsed.value });
  if (error) return failure(error, 'The leave could not be rejected.');
  return done('Leave rejected.');
}
