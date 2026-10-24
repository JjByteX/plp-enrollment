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

export type IntakeBody =
  | { status: 'created' | 'updated' | 'unchanged'; applicant_ref: string }
  | { error: string };
export type IntakeOutcome = { httpStatus: number; body: IntakeBody };

type Applied =
  | { ok: true; result: 'created' | 'updated' | 'unchanged'; applicantId: string }
  | { ok: false; httpStatus: number; reason: string };

const reject = (httpStatus: number, reason: string): Applied => ({ ok: false, httpStatus, reason });

type ApplicantRow = { id: string; user_id: string; program_id: string; admission_date: string; admission_type: string };
type UserRow = { id: string; auth_id: string; role: string; email: string; full_name: string };

async function apply(admin: SupabaseClient, input: IntakePayload): Promise<Applied> {
  const { data: programs, error: programsError } = await admin.from('programs').select('id, code');
  if (programsError) return reject(500, 'Could not read the program list.');
  const program = ((programs ?? []) as { id: string; code: string }[]).find(
    (p) => p.code.toLowerCase() === input.program_code.toLowerCase()
  );
  if (!program) return reject(422, `Program code "${input.program_code}" is not recognized.`);

  const { data: existingRow, error: existingError } = await admin
    .from('applicants')
    .select('id, user_id, program_id, admission_date, admission_type')
    .eq('applicant_ref', input.applicant_ref)
    .maybeSingle();
  if (existingError) return reject(500, 'Could not look up the applicant.');
  const existing = existingRow as ApplicantRow | null;

  if (existing) return refresh(admin, existing, input, program.id);
  return create(admin, input, program.id);
}

// Same applicant sent again: details refresh while they are still an
// Applicant. Once they are a Student nothing changes.
async function refresh(admin: SupabaseClient, existing: ApplicantRow, input: IntakePayload, programId: string): Promise<Applied> {
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
    existing.admission_type === input.admission_type;
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
    .update({ program_id: programId, admission_date: input.admission_date, admission_type: input.admission_type })
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
    return { httpStatus: applied.result === 'created' ? 201 : 200, body: { status: applied.result, applicant_ref: fields.applicant_ref } };
  }
  return { httpStatus: applied.httpStatus, body: { error: applied.reason } };
}
