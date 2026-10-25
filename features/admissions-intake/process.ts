// features/admissions-intake/process.ts
//
// Handles one request from Admissions, or an Admin resend of a stored one.
// There is no signed-in person here, so this uses the service role client
// (lib/supabase/admin.ts) and writes as the system (audit actor is empty).
// Safe to repeat: the applicant ref makes a second send a refresh, never a
// second account. Every request, accepted or rejected, ends up in
// admissions_intake_log.
import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminClient } from '@/lib/supabase/admin';
import { logFieldsFor, parseIntakePayload, type IntakePayload } from './schema';

// The visit the applicant was booked into at intake, when a slot was free.
// Times are Manila time, written HH:MM (24 hour).
export type IntakeVisit = { date: string; start_time: string; end_time: string; office_name: string };

export type IntakeBody =
  | { status: 'created' | 'updated' | 'unchanged'; applicant_ref: string; visit?: IntakeVisit }
  | { error: string };
export type IntakeOutcome = { httpStatus: number; body: IntakeBody };

type Applied =
  | { ok: true; result: 'created' | 'updated' | 'unchanged'; applicantId: string; visit?: IntakeVisit | null }
  | { ok: false; httpStatus: number; reason: string };

const reject = (httpStatus: number, reason: string): Applied => ({ ok: false, httpStatus, reason });

type ApplicantRow = {
  id: string;
  user_id: string;
  program_id: string;
  admission_date: string;
  admission_type: string;
  admissions_verified_docs: string[] | null;
  withdrawn_at: string | null;
};
type UserRow = { id: string; auth_id: string; role: string; email: string; full_name: string };

function sameList(a: string[], b: string[]): boolean {
  const left = [...a].sort();
  const right = [...b].sort();
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

async function apply(admin: SupabaseClient, input: IntakePayload): Promise<Applied> {
  const { data: programs, error: programsError } = await admin.from('programs').select('id, code');
  if (programsError) return reject(500, 'Could not read the program list.');
  const program = ((programs ?? []) as { id: string; code: string }[]).find(
    (p) => p.code.toLowerCase() === input.program_code.toLowerCase()
  );
  if (!program) return reject(422, `Program code "${input.program_code}" is not recognized.`);

  const { data: existingRow, error: existingError } = await admin
    .from('applicants')
    .select('id, user_id, program_id, admission_date, admission_type, admissions_verified_docs, withdrawn_at')
    .eq('applicant_ref', input.applicant_ref)
    .maybeSingle();
  if (existingError) return reject(500, 'Could not look up the applicant.');
  const existing = existingRow as ApplicantRow | null;

  const applied = existing ? await refresh(admin, existing, input, program.id) : await create(admin, input, program.id);
  if (!applied.ok) return applied;
  return { ...applied, visit: await autoAssignVisit(admin, applied.applicantId) };
}

function readVisit(value: unknown): IntakeVisit | null {
  if (typeof value !== 'object' || value === null) return null;
  const visit = value as Record<string, unknown>;
  const { date, start_time, end_time, office_name } = visit;
  if (typeof date !== 'string' || typeof start_time !== 'string') return null;
  if (typeof end_time !== 'string' || typeof office_name !== 'string') return null;
  return { date, start_time, end_time, office_name };
}

// Books the earliest open visit slot for the applicant's program, the way the
// Registrar's "Assign all unassigned" button would, so the Registrar only has
// to step in when no slot is free. Repeating it is safe: an applicant who is
// already booked keeps that visit, and a student is skipped. A failure here is
// logged and never blocks the handoff; the Registrar can still assign by hand.
async function autoAssignVisit(admin: SupabaseClient, applicantId: string): Promise<IntakeVisit | null> {
  try {
    const { data, error } = await admin.rpc('auto_assign_visit', { p_applicant: applicantId });
    if (error) {
      console.error('Automatic visit assignment failed', error);
      return null;
    }
    return readVisit(data);
  } catch (error) {
    console.error('Automatic visit assignment failed', error);
    return null;
  }
}

// Same applicant sent again: details refresh while they are still an
// Applicant. Once they are a Student nothing changes. Someone who withdrew
// (step 17) stays withdrawn: a resend changes nothing and books no visit.
async function refresh(admin: SupabaseClient, existing: ApplicantRow, input: IntakePayload, programId: string): Promise<Applied> {
  if (existing.withdrawn_at) return { ok: true, result: 'unchanged', applicantId: existing.id };

  const { data: userData, error: userError } = await admin
    .from('users')
    .select('id, auth_id, role, email, full_name')
    .eq('id', existing.user_id)
    .single();
  if (userError || !userData) return reject(500, 'Could not read the applicant account.');
  const user = userData as UserRow;

  if (user.role !== 'applicant') return { ok: true, result: 'unchanged', applicantId: existing.id };

  const emailChanged = user.email.toLowerCase() !== input.email;
  const same =
    !emailChanged &&
    user.full_name === input.full_name &&
    existing.program_id === programId &&
    existing.admission_date === input.admission_date &&
    existing.admission_type === input.admission_type &&
    sameList(existing.admissions_verified_docs ?? [], input.verified_documents);
  if (same) return { ok: true, result: 'unchanged', applicantId: existing.id };

  if (emailChanged) {
    const { data: taken } = await admin.from('users').select('id').eq('email', input.email).neq('id', user.id).maybeSingle();
    if (taken) return reject(409, 'This email already belongs to another account.');
    const { error: authError } = await admin.auth.admin.updateUserById(user.auth_id, { email: input.email, email_confirm: true });
    if (authError) return reject(409, 'The email could not be changed on the account.');
  }

  const { error: userUpdateError } = await admin
    .from('users')
    .update({ full_name: input.full_name, email: input.email })
    .eq('id', user.id);
  if (userUpdateError) return reject(500, 'Could not update the applicant account.');

  const { error: applicantUpdateError } = await admin
    .from('applicants')
    .update({
      program_id: programId,
      admission_date: input.admission_date,
      admission_type: input.admission_type,
      admissions_verified_docs: input.verified_documents,
    })
    .eq('id', existing.id);
  if (applicantUpdateError) return reject(500, 'Could not update the applicant.');

  return { ok: true, result: 'updated', applicantId: existing.id };
}

// New applicant: create the login (the invite email carries the
// set-password link), then the users and applicants rows. If a row fails the
// new login is removed, so nothing half-made is left behind.
async function create(admin: SupabaseClient, input: IntakePayload, programId: string): Promise<Applied> {
  const { data: taken } = await admin.from('users').select('id').eq('email', input.email).maybeSingle();
  if (taken) return reject(409, 'This email already belongs to another account.');

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(input.email, {
    data: { full_name: input.full_name },
  });
  if (inviteError || !invited.user) {
    if (inviteError?.status === 429) return reject(503, 'Too many emails sent. Try again later.');
    if (inviteError?.message.toLowerCase().includes('registered')) {
      return reject(409, 'This email already has an account.');
    }
    return reject(502, 'The invitation email could not be sent.');
  }

  // Only remove a login this call just made.
  const justCreated = Date.now() - new Date(invited.user.created_at).getTime() < 60_000;
  const undo = async () => {
    if (justCreated) await admin.auth.admin.deleteUser(invited.user.id);
  };

  const { data: userRow, error: userInsertError } = await admin
    .from('users')
    .insert({ auth_id: invited.user.id, full_name: input.full_name, email: input.email, role: 'applicant' })
    .select('id')
    .single();
  if (userInsertError || !userRow) {
    await undo();
    return reject(500, 'Could not create the applicant account.');
  }

  const { data: applicantRow, error: applicantInsertError } = await admin
    .from('applicants')
    .insert({
      user_id: (userRow as { id: string }).id,
      applicant_ref: input.applicant_ref,
      program_id: programId,
      admission_date: input.admission_date,
      admission_type: input.admission_type,
      admissions_verified_docs: input.verified_documents,
    })
    .select('id')
    .single();
  if (applicantInsertError || !applicantRow) {
    await undo();
    return reject(500, 'Could not create the applicant.');
  }

  return { ok: true, result: 'created', applicantId: (applicantRow as { id: string }).id };
}

export async function processIntake(raw: unknown, sourceOverride?: string): Promise<IntakeOutcome> {
  const admin = createAdminClient();
  const parsed = parseIntakePayload(raw);
  const fields = logFieldsFor(raw, parsed);
  const source = sourceOverride ?? fields.source_name;

  let applied: Applied;
  try {
    const { data: settings } = await admin
      .from('admissions_connection_settings')
      .select('is_enabled')
      .eq('id', true)
      .maybeSingle();

    if (settings && !(settings as { is_enabled: boolean }).is_enabled) {
      applied = reject(503, 'The connection from Admissions is switched off.');
    } else if (!parsed.ok) {
      applied = reject(400, parsed.reason);
    } else {
      applied = await apply(admin, parsed.value);
    }
  } catch (error) {
    console.error('Admissions intake failed', error);
    applied = reject(500, 'Unexpected error while handling the request.');
  }

  const { error: logError } = await admin.from('admissions_intake_log').insert({
    ...fields,
    source_name: source.slice(0, 60),
    status: applied.ok ? 'accepted' : 'rejected',
    rejection_reason: applied.ok ? null : applied.reason,
    raw_payload: typeof raw === 'object' && raw !== null ? raw : { value: String(raw).slice(0, 1000) },
    resulting_applicant_id: applied.ok ? applied.applicantId : null,
  });
  if (logError) console.error('Could not write the intake log', logError);

  if (applied.ok) {
    return {
      httpStatus: applied.result === 'created' ? 201 : 200,
      body: {
        status: applied.result,
        applicant_ref: fields.applicant_ref,
        ...(applied.visit ? { visit: applied.visit } : {}),
      },
    };
  }
  return { httpStatus: applied.httpStatus, body: { error: applied.reason } };
}
