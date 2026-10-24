'use server';

// features/admissions-intake/actions.ts
//
// Admin actions for the Admissions connection: switch it on or off, and
// resend a rejected request. Both check the caller is an Admin. The switch
// runs under the Admin's own session, so it is audit logged with who did it.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/auth/session';
import { processIntake } from './process';

export type IntakeActionResult = { ok: true; message: string } | { error: string };

export async function setConnectionEnabled(enabled: boolean): Promise<IntakeActionResult> {
  const actor = await getCurrentUser();
  if (!actor || actor.role !== 'admin') return { error: 'Only an Admin can change this.' };

  const supabase = createClient();
  const { error } = await supabase
    .from('admissions_connection_settings')
    .update({ is_enabled: enabled, updated_by: actor.id, updated_at: new Date().toISOString() })
    .eq('id', true);
  if (error) return { error: 'The setting could not be saved.' };

  revalidatePath('/admin/admissions');
  return { ok: true, message: enabled ? 'Connection switched on.' : 'Connection switched off.' };
}

// Runs a stored rejected request again, for example after the connection was
// switched back on or a program was added. The new attempt is logged as its own row.
export async function resendIntake(logId: string): Promise<IntakeActionResult> {
  const actor = await getCurrentUser();
  if (!actor || actor.role !== 'admin') return { error: 'Only an Admin can resend a request.' };

  const supabase = createClient();
  const { data } = await supabase
    .from('admissions_intake_log')
    .select('status, raw_payload')
    .eq('id', logId)
    .maybeSingle();
  const row = data as { status: string; raw_payload: unknown } | null;
  if (!row) return { error: 'That request was not found.' };
  if (row.status !== 'rejected') return { error: 'Only a rejected request can be resent.' };

  const outcome = await processIntake(row.raw_payload, 'Admin resend');
  revalidatePath('/admin/admissions');
  if ('error' in outcome.body) return { error: outcome.body.error };
  return { ok: true, message: 'Request accepted.' };
}
