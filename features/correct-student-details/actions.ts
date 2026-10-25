'use server';

// features/correct-student-details/actions.ts
//
// The Registrar or Admin corrects a student's name or email after promotion.
// The caller is checked first. The database function runs under the caller's
// own session so row level security applies and the audit log records who did
// it (decision-log.md #10).
//
// The sign-in email lives in Supabase Auth as well as in users, so a changed
// email is written there first (service role, the way the Admissions intake
// does it) and put back if the database refuses. The name needs no such step.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';
import { getCurrentUser } from '@/lib/auth/session';
import { parseCorrectInput, type CorrectInput } from './schema';

export type CorrectActionResult = { ok: true; message: string } | { error: string };

// Messages the database raises on purpose (P0001) are written for the person
// who sees them, so show them. Anything else gets a plain message.
function failure(error: { code?: string; message: string }, fallback: string): { error: string } {
  if (error.code === 'P0001') return { error: error.message };
  return { error: fallback };
}

export async function correctStudentDetails(input: CorrectInput): Promise<CorrectActionResult> {
  const actor = await getCurrentUser();
  if (!actor || (actor.role !== 'registrar' && actor.role !== 'admin')) {
    return { error: 'Only the Registrar or Admin can correct a student\'s details.' };
  }

  const parsed = parseCorrectInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { applicantId, fullName, email, reason } = parsed.value;

  const supabase = createClient();
  const { data: applicant } = await supabase.from('applicants').select('user_id').eq('id', applicantId).maybeSingle();
  const userId = (applicant as { user_id: string } | null)?.user_id;
  if (!userId) return { error: 'Student not found.' };

  const admin = createAdminClient();
  const { data: userData } = await admin.from('users').select('auth_id, email').eq('id', userId).maybeSingle();
  const current = userData as { auth_id: string; email: string } | null;
  if (!current) return { error: 'Student not found.' };

  const emailChanged = current.email.toLowerCase() !== email;
  if (emailChanged) {
    const { data: taken } = await admin.from('users').select('id').eq('email', email).neq('id', userId).maybeSingle();
    if (taken) return { error: 'This email already belongs to another account.' };
    const { error: authError } = await admin.auth.admin.updateUserById(current.auth_id, { email, email_confirm: true });
    if (authError) return { error: 'The sign-in email could not be changed. Nothing was saved.' };
  }

  const { error } = await supabase.rpc('correct_student_details', {
    p_applicant: applicantId,
    p_full_name: fullName,
    p_email: email,
    p_reason: reason,
  });
  if (error) {
    if (emailChanged) {
      await admin.auth.admin.updateUserById(current.auth_id, { email: current.email, email_confirm: true });
    }
    return failure(error, 'The correction could not be saved. Try again.');
  }

  revalidatePath('/', 'layout');
  return { ok: true, message: 'Corrected. The student was told.' };
}
