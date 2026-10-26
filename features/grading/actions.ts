'use server';

// features/grading/actions.ts
//
// Actions for the grading scale and grades (step 19). Each checks the caller's
// role, then calls a database function that checks it again and enforces the
// chain: the Professor enters and submits, the Dean approves (which locks the
// grades), and a change to an approved grade is proposed by the Professor,
// signed by the Dean and approved by the Registrar. Messages the database
// raises on purpose (P0001) are shown as written.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/auth/session';
import type { Role } from '@/lib/auth/roles';
import { UUID, parseReason, parseScale, type GradeEntry } from './schema';

export type GradingActionResult = { ok: true; message: string } | { error: string };

const PAGES = ['/professor/grades', '/dean/grades', '/registrar/grades', '/admin/content'];

async function allowed(roles: readonly Role[]): Promise<boolean> {
  const actor = await getCurrentUser();
  return actor !== null && roles.includes(actor.role);
}

function failure(error: { code?: string; message: string }, fallback: string): { error: string } {
  return error.code === 'P0001' ? { error: error.message } : { error: fallback };
}

function done(message: string): GradingActionResult {
  for (const page of PAGES) revalidatePath(page);
  return { ok: true, message };
}

const PROFESSOR: readonly Role[] = ['professor', 'admin'];
const DEAN: readonly Role[] = ['dean', 'admin'];
const REGISTRAR: readonly Role[] = ['registrar', 'admin'];

export async function saveScale(input: unknown): Promise<GradingActionResult> {
  if (!(await allowed(['admin']))) return { error: 'Only Admin can set the grading scale.' };
  const parsed = parseScale(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('save_grade_scale', {
    p_bands: parsed.value.bands.map((band) => ({
      label: band.label,
      outcome: band.outcome,
      descriptive: band.descriptive,
      from: band.from,
      to: band.to,
    })),
    p_inc_days: parsed.value.incWindowDays,
  });
  if (error) return failure(error, 'The grading scale could not be saved.');
  return done('Grading scale saved. Grades already recorded keep their outcome.');
}

function ids(sectionId: unknown, subjectId: unknown): { sectionId: string; subjectId: string } | null {
  return typeof sectionId === 'string' && typeof subjectId === 'string' && UUID.test(sectionId) && UUID.test(subjectId)
    ? { sectionId, subjectId }
    : null;
}

export async function saveGrades(sectionId: string, subjectId: string, entries: GradeEntry[]): Promise<GradingActionResult> {
  if (!(await allowed(PROFESSOR))) return { error: 'Only the Professor of this subject can enter grades.' };
  const key = ids(sectionId, subjectId);
  if (!key || !Array.isArray(entries)) return { error: 'That subject was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('save_grades', {
    p_section: key.sectionId,
    p_subject: key.subjectId,
    p_grades: entries.map((entry) => ({ studentId: entry.studentId, grade: entry.grade })),
  });
  if (error) return failure(error, 'The grades could not be saved.');
  return done('Grades saved.');
}

export async function submitGrades(sectionId: string, subjectId: string): Promise<GradingActionResult> {
  if (!(await allowed(PROFESSOR))) return { error: 'Only the Professor of this subject can submit grades.' };
  const key = ids(sectionId, subjectId);
  if (!key) return { error: 'That subject was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('submit_grades', { p_section: key.sectionId, p_subject: key.subjectId });
  if (error) return failure(error, 'The grades could not be submitted.');
  return done('Grades submitted. They wait for the Dean.');
}

export async function approveGrades(sectionId: string, subjectId: string): Promise<GradingActionResult> {
  if (!(await allowed(DEAN))) return { error: 'Only the Dean of this college can approve grades.' };
  const key = ids(sectionId, subjectId);
  if (!key) return { error: 'That subject was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('approve_grades', { p_section: key.sectionId, p_subject: key.subjectId });
  if (error) return failure(error, 'The grades could not be approved.');
  return done('Grades approved and locked.');
}

export async function returnGrades(sectionId: string, subjectId: string, reason: string): Promise<GradingActionResult> {
  if (!(await allowed(DEAN))) return { error: 'Only the Dean of this college can return grades.' };
  const key = ids(sectionId, subjectId);
  if (!key) return { error: 'That subject was not found.' };
  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('return_grades', {
    p_section: key.sectionId,
    p_subject: key.subjectId,
    p_reason: parsed.value,
  });
  if (error) return failure(error, 'The grades could not be returned.');
  return done('Grades returned to the Professor.');
}

export async function proposeChange(gradeId: string, newGrade: string, reason: string): Promise<GradingActionResult> {
  if (!(await allowed(PROFESSOR))) return { error: 'Only the Professor of this subject can propose a grade change.' };
  if (typeof gradeId !== 'string' || !UUID.test(gradeId)) return { error: 'That grade was not found.' };
  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('propose_grade_change', {
    p_grade: gradeId,
    p_new_grade: typeof newGrade === 'string' ? newGrade : '',
    p_reason: parsed.value,
  });
  if (error) return failure(error, 'The change could not be proposed.');
  return done('Change proposed. It waits for the Dean, then the Registrar.');
}

export async function signChange(changeId: string): Promise<GradingActionResult> {
  if (!(await allowed(DEAN))) return { error: 'Only the Dean of this college can sign a grade change.' };
  if (typeof changeId !== 'string' || !UUID.test(changeId)) return { error: 'That change was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('sign_grade_change', { p_change: changeId });
  if (error) return failure(error, 'The change could not be signed.');
  return done('Change signed. It waits for the Registrar.');
}

export async function approveChange(changeId: string): Promise<GradingActionResult> {
  if (!(await allowed(REGISTRAR))) return { error: 'Only the Registrar can approve a grade change.' };
  if (typeof changeId !== 'string' || !UUID.test(changeId)) return { error: 'That change was not found.' };

  const supabase = createClient();
  const { error } = await supabase.rpc('approve_grade_change', { p_change: changeId });
  if (error) return failure(error, 'The change could not be approved.');
  return done('Change approved. The grade is updated.');
}

export async function rejectChange(changeId: string, reason: string): Promise<GradingActionResult> {
  if (!(await allowed(['dean', 'registrar', 'admin']))) return { error: 'Only the Dean or the Registrar can reject a grade change.' };
  if (typeof changeId !== 'string' || !UUID.test(changeId)) return { error: 'That change was not found.' };
  const parsed = parseReason(reason);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase.rpc('reject_grade_change', { p_change: changeId, p_reason: parsed.value });
  if (error) return failure(error, 'The change could not be rejected.');
  return done('Change rejected.');
}
