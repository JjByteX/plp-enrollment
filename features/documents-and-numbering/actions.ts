'use server';

// features/documents-and-numbering/actions.ts
//
// Registrar (or Admin) actions for the documents checklist and for marking
// documents received. Every action checks the caller first, then runs under
// the caller's own session so row level security applies and the audit log
// records who did it (decision-log.md #10). Promotion goes through the
// database function mark_documents_received, so the student number, the role
// change, the visit booking and the notification are one transaction.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failureWith } from '@/lib/failure';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { notifyStudentStage } from '@/features/admissions-callback/send';
import { UUID, parseTickInput } from './schema';

export type DocumentActionResult = { ok: true; message: string } | { error: string };
export type PromoteResult = { ok: true; message: string; studentNumber: string | null } | { error: string };

const PAGE = '/registrar/documents';

async function requireStaff(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'registrar' || actor.role === 'admin') ? actor : null;
}

// 23505 is a document ticked twice.
const failure = failureWith({ '23505': 'That document is already ticked.' });

// Tick or untick one document, or change its note. Required items cannot be
// changed once the applicant is a student (the database refuses and says so).
export async function setDocumentReceived(input: unknown): Promise<DocumentActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can update documents.' };

  const parsed = parseTickInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { applicantId, docType, received, note } = parsed.value;

  const supabase = createClient();

  if (!received) {
    const { error } = await supabase
      .from('documents')
      .delete()
      .eq('applicant_id', applicantId)
      .eq('doc_type', docType);
    if (error) return failure(error, 'The document could not be updated.');
    revalidatePath(PAGE);
    return { ok: true, message: 'Document unmarked.' };
  }

  const { data: existing, error: readError } = await supabase
    .from('documents')
    .select('id')
    .eq('applicant_id', applicantId)
    .eq('doc_type', docType)
    .maybeSingle();
  if (readError) return failure(readError, 'The document could not be updated.');

  const { error } = existing
    ? await supabase.from('documents').update({ note }).eq('applicant_id', applicantId).eq('doc_type', docType)
    : await supabase.from('documents').insert({ applicant_id: applicantId, doc_type: docType, note });
  if (error) return failure(error, 'The document could not be updated.');

  revalidatePath(PAGE);
  return { ok: true, message: existing ? 'Note saved.' : 'Document received.' };
}

// Gives the student number and turns the applicant into a student. The
// database refuses it while a required document is missing (no override) and
// names what is missing, so that message is passed on as written.
export async function markDocumentsReceived(applicantId: string): Promise<PromoteResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can mark documents received.' };
  if (typeof applicantId !== 'string' || !UUID.test(applicantId)) return { error: 'Choose an applicant.' };

  const supabase = createClient();
  const { data, error } = await supabase.rpc('mark_documents_received', { p_applicant: applicantId });
  if (error) return failure(error, 'The documents could not be marked received. Try again.');

  const studentId = typeof data === 'string' ? data : null;
  let studentNumber: string | null = null;
  if (studentId) {
    const { data: student } = await supabase
      .from('students')
      .select('student_number')
      .eq('id', studentId)
      .maybeSingle();
    studentNumber = (student as { student_number: string } | null)?.student_number ?? null;
  }

  // Tell Admissions. Best effort: it never blocks or fails the promotion.
  if (studentId) await notifyStudentStage(supabase, studentId, 'student');

  revalidatePath(PAGE);
  return {
    ok: true,
    studentNumber,
    message: studentNumber ? `Documents received. Student number ${studentNumber}.` : 'Documents received.',
  };
}
