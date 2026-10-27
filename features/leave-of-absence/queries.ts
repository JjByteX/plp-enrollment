// features/leave-of-absence/queries.ts
//
// Reads for leave of absence and readmission (step 23). Each calls a database function that
// checks the caller's role and college itself, so nobody reads more than they may.
import { createClient } from '@/lib/supabase/server';
import type { LeaveOverview, LeaveRequest, OnLeaveStudent, Readmission } from './schema';

// A leave that is approved starts, and one that has run its terms ends, when the term changes. This
// also catches up on a page load, so a list never shows a leave in the wrong state.
export async function catchUpLeaves(): Promise<void> {
  const supabase = createClient();
  await supabase.rpc('leave_catch_up');
}

export async function getLeaveOverview(studentId: string): Promise<LeaveOverview | { error: string }> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc('leave_overview', { p_student: studentId });
  if (error) return { error: error.code === 'P0001' ? error.message : 'The leaves could not be read.' };
  if (!data) return { error: 'The leaves could not be read.' };
  return data as LeaveOverview;
}

// Leaves waiting for the Dean, limited to the Dean's college by the database.
export async function listLeaveRequests(): Promise<LeaveRequest[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('leave_requests');
  return Array.isArray(data) ? (data as LeaveRequest[]) : [];
}

export async function listStudentsOnLeave(): Promise<OnLeaveStudent[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('students_on_leave');
  return Array.isArray(data) ? (data as OnLeaveStudent[]) : [];
}

export async function getMyReadmission(): Promise<Readmission | null> {
  const supabase = createClient();
  const { data } = await supabase.rpc('my_readmission');
  return data ? (data as Readmission) : null;
}
