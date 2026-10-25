// features/admissions-callback/send.ts
//
// Tells PLP Admissions how far an applicant has come, so its staff see
// "Student 2026-00012" and "Enrolled" instead of only "Sent to Enrollment"
// (open-questions.md #3 and #11). Two stages: 'student' (documents received,
// student number given) and 'enrolled' (COR issued).
//
// Safe to repeat: Admissions only moves an applicant forward, so sending the
// same stage twice changes nothing. A failure is logged and never blocks the
// Registrar's action. Does nothing until both settings exist:
//   ADMISSIONS_STATUS_URL     full URL of Admissions' /api/enrollment-status
//   ADMISSIONS_STATUS_SECRET  must equal ENROLLMENT_STATUS_SECRET in Admissions
//
// Catch-up: the stage Admissions last accepted is kept per student in
// admissions_status_queue. A send that fails is therefore not lost:
// catchUpAdmissionsStatus() (called when the Registrar opens the Documents and
// COR pages) sends again what Admissions is missing, waiting 5 minutes longer
// after each failure, and gives up after 20 attempts or when Admissions refuses
// the details (for example an unknown applicant reference). Turning the
// settings on later also sends every student Admissions has not been told about.
import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminClient } from '@/lib/supabase/admin';

export type AdmissionsStage = 'student' | 'enrolled';

type StatusEvent = { studentId: string; applicantRef: string; stage: AdmissionsStage; studentNumber: string };
type Outcome = { ok: true } | { ok: false; error: string; permanent: boolean };
type Target = { url: string; secret: string };

const TIMEOUT_MS = 5000;
const CATCH_UP_LIMIT = 5; // keeps a page fast when Admissions is slow

function target(): Target | null {
  const url = process.env.ADMISSIONS_STATUS_URL?.trim();
  const secret = process.env.ADMISSIONS_STATUS_SECRET?.trim();
  return url && secret ? { url, secret } : null;
}

// A refusal that sending again cannot fix (unknown applicant, bad details) is
// permanent. A wrong secret (401), a busy or switched-off Admissions (429, 503)
// and any server error are worth trying again.
function isPermanent(status: number): boolean {
  return status >= 400 && status < 500 && status !== 401 && status !== 408 && status !== 429;
}

async function send(event: StatusEvent, to: Target): Promise<Outcome> {
  try {
    const response = await fetch(to.url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${to.secret}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        applicant_ref: event.applicantRef,
        stage: event.stage,
        student_number: event.studentNumber,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
      redirect: 'manual',
    });
    if (response.ok) return { ok: true };
    console.error(`Admissions status call answered ${response.status} for ${event.applicantRef}`);
    return { ok: false, error: `Admissions answered HTTP ${response.status}.`, permanent: isPermanent(response.status) };
  } catch (error) {
    console.error('Admissions status call failed', error);
    return { ok: false, error: 'Could not reach Admissions.', permanent: false };
  }
}

// Remembers what Admissions accepted (or why it did not), so the catch-up knows.
async function record(admin: SupabaseClient, event: StatusEvent, outcome: Outcome) {
  try {
    const { error } = await admin.rpc('record_admissions_status', {
      p_student: event.studentId,
      p_stage: event.stage,
      p_ok: outcome.ok,
      p_error: outcome.ok ? null : outcome.error,
      p_permanent: outcome.ok ? false : outcome.permanent,
    });
    if (error) console.error('Could not record the Admissions status', error);
  } catch (error) {
    console.error('Could not record the Admissions status', error);
  }
}

async function post(event: StatusEvent): Promise<void> {
  const to = target();
  if (!to) return;
  const outcome = await send(event, to);
  try {
    await record(createAdminClient(), event, outcome);
  } catch (error) {
    console.error('Could not record the Admissions status', error);
  }
}

type StudentRow = {
  id: string;
  student_number: string;
  applicants: { applicant_ref: string } | { applicant_ref: string }[] | null;
};

function toEvent(row: StudentRow, stage: AdmissionsStage): StatusEvent | null {
  const applicant = Array.isArray(row.applicants) ? row.applicants[0] : row.applicants;
  return applicant
    ? { studentId: row.id, applicantRef: applicant.applicant_ref, stage, studentNumber: row.student_number }
    : null;
}

// One student, by id (read under the signed-in person's session).
export async function notifyStudentStage(supabase: SupabaseClient, studentId: string, stage: AdmissionsStage) {
  const { data } = await supabase
    .from('students')
    .select('id, student_number, applicants(applicant_ref)')
    .eq('id', studentId)
    .maybeSingle();
  const event = data ? toEvent(data as unknown as StudentRow, stage) : null;
  if (event) await post(event);
}

// Every student whose COR was issued at or after `sinceIso` (bulk issuing).
export async function notifyEnrolledSince(supabase: SupabaseClient, sinceIso: string) {
  const { data } = await supabase
    .from('cors')
    .select('students(id, student_number, applicants(applicant_ref))')
    .gte('issued_at', sinceIso)
    .limit(500);
  const rows = ((data ?? []) as unknown as { students: StudentRow | StudentRow[] | null }[])
    .map((row) => (Array.isArray(row.students) ? row.students[0] : row.students))
    .filter((row): row is StudentRow => Boolean(row));
  const events = rows.map((row) => toEvent(row, 'enrolled')).filter((event): event is StatusEvent => event !== null);
  await Promise.all(events.map(post));
}

type DueRow = { student_id: string; applicant_ref: string; student_number: string; stage: AdmissionsStage };

// Sends again what Admissions is missing. Never throws. Stops at the first
// failure that may be temporary, because that usually means Admissions is down
// and the next try would only make the page wait.
export async function catchUpAdmissionsStatus(): Promise<void> {
  const to = target();
  if (!to) return;
  try {
    const admin = createAdminClient();
    const { data, error } = await admin.rpc('admissions_status_due', { p_limit: CATCH_UP_LIMIT });
    if (error) {
      console.error('Could not read the Admissions status queue', error);
      return;
    }
    for (const row of (data ?? []) as DueRow[]) {
      const event: StatusEvent = {
        studentId: row.student_id,
        applicantRef: row.applicant_ref,
        stage: row.stage,
        studentNumber: row.student_number,
      };
      const outcome = await send(event, to);
      await record(admin, event, outcome);
      if (!outcome.ok && !outcome.permanent) break;
    }
  } catch (error) {
    console.error('Admissions status catch-up failed', error);
  }
}
