'use server';

// features/reschedule-mass/actions.ts
//
// Registrar (or Admin) action for the mass reschedule (typhoon, class
// suspension, office closure). The caller is checked first, then the database
// function moves every booked visit on the date to the next open slot, writes
// each person's notification and puts the reason in the audit log, all in one
// transaction. Staff do not pick a target slot: a person who does not fit
// stays where they are and is counted, so slots are added and it is run again
// (decision-log.md #23).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { parseMassInput, visitCount, type MassInput } from './schema';

export type MassActionResult = { ok: true; message: string } | { error: string };

async function requireStaff(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'registrar' || actor.role === 'admin') ? actor : null;
}

export async function massReschedule(input: MassInput): Promise<MassActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can set a mass reschedule.' };

  const parsed = parseMassInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { date, programId, officeName, reason } = parsed.value;

  const supabase = createClient();
  const { data, error } = await supabase.rpc('mass_reschedule', {
    p_date: date,
    p_program: programId,
    p_office: officeName,
    p_reason: reason,
  });
  if (error) {
    // Messages the database raises on purpose (P0001) are written for the Registrar.
    return { error: error.code === 'P0001' ? error.message : 'The visits could not be moved. Try again.' };
  }

  const row = (Array.isArray(data) ? data[0] : data) as { moved?: number; left_over?: number } | null;
  const moved = row?.moved ?? 0;
  const leftOver = row?.left_over ?? 0;

  revalidatePath('/registrar/reschedules');
  revalidatePath('/registrar/visits');
  if (leftOver > 0) {
    return {
      ok: true,
      message: `${visitCount(moved)} moved. ${visitCount(leftOver)} stayed because no other date has a free seat: add slots for these programs, then run it again.`,
    };
  }
  return { ok: true, message: `${visitCount(moved)} moved. Each person was told.` };
}
