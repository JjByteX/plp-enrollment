// features/admissions-callback/send.ts
//
// Tells PLP Admissions how far an applicant has come, so its staff see
// "Student 2026-00012" and "Enrolled" instead of only "Sent to Enrollment"
// (open-questions.md #3 and #11). Two stages: 'student' (documents received,
// student number given) and 'enrolled' (COR issued).
//
// Best effort and safe to repeat: Admissions only moves an applicant forward,
// so sending the same stage twice changes nothing. A failure is logged and
// never blocks the Registrar's action. Does nothing until both settings exist:
//   ADMISSIONS_STATUS_URL     full URL of Admissions' /api/enrollment-status
//   ADMISSIONS_STATUS_SECRET  must equal ENROLLMENT_STATUS_SECRET in Admissions
import type { SupabaseClient } from '@supabase/supabase-js';

export type AdmissionsStage = 'student' | 'enrolled';

type StatusEvent = { applicantRef: string; stage: AdmissionsStage; studentNumber: string };

const TIMEOUT_MS = 5000;

async function post(event: StatusEvent): Promise<void> {
  const url = process.env.ADMISSIONS_STATUS_URL?.trim();
  const secret = process.env.ADMISSIONS_STATUS_SECRET?.trim();
  if (!url || !secret) return;

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        applicant_ref: event.applicantRef,
        stage: event.stage,
        student_number: event.studentNumber,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
      redirect: 'manual',
    });
    if (!response.ok) console.error(`Admissions status call answered ${response.status} for ${event.applicantRef}`);
  } catch (error) {
    console.error('Admissions status call failed', error);
  }
}

type StudentRow = { student_number: string; applicants: { applicant_ref: string } | { applicant_ref: string }[] | null };

function toEvent(row: StudentRow, stage: AdmissionsStage): StatusEvent | null {
  const applicant = Array.isArray(row.applicants) ? row.applicants[0] : row.applicants;
  return applicant ? { applicantRef: applicant.applicant_ref, stage, studentNumber: row.student_number } : null;
}

// One student, by id (read under the signed-in person's session).
export async function notifyStudentStage(supabase: SupabaseClient, studentId: string, stage: AdmissionsStage) {
  const { data } = await supabase
    .from('students')
    .select('student_number, applicants(applicant_ref)')
    .eq('id', studentId)
    .maybeSingle();
  const event = data ? toEvent(data as unknown as StudentRow, stage) : null;
  if (event) await post(event);
}

// Every student whose COR was issued at or after `sinceIso` (bulk issuing).
export async function notifyEnrolledSince(supabase: SupabaseClient, sinceIso: string) {
  const { data } = await supabase
    .from('cors')
    .select('students(student_number, applicants(applicant_ref))')
    .gte('issued_at', sinceIso)
    .limit(500);
  const rows = ((data ?? []) as unknown as { students: StudentRow | StudentRow[] | null }[])
    .map((row) => (Array.isArray(row.students) ? row.students[0] : row.students))
    .filter((row): row is StudentRow => Boolean(row));
  const events = rows.map((row) => toEvent(row, 'enrolled')).filter((event): event is StatusEvent => event !== null);
  await Promise.all(events.map(post));
}
