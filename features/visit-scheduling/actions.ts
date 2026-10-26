'use server';

// features/visit-scheduling/actions.ts
//
// Registrar (or Admin) actions for visit slots and assignments. Every action
// checks the caller first, then runs under the caller's own session so row
// level security applies and the audit log records who did it. Assigning and
// moving go through database functions, so the booking and its notification
// are one transaction (plan decision C).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { failureWith } from '@/lib/failure';
import { getCurrentUser, type CurrentUser } from '@/lib/auth/session';
import { MAX_REASON, UUID, parseSlotInput, type SlotInput } from './schema';

export type VisitActionResult = { ok: true; message: string } | { error: string };

const PAGE = '/registrar/visits';

async function requireStaff(): Promise<CurrentUser | null> {
  const actor = await getCurrentUser();
  return actor && (actor.role === 'registrar' || actor.role === 'admin') ? actor : null;
}

// 23505 is a slot that already exists.
const failure = failureWith({ '23505': 'A slot for this program, date, start time and office already exists.' });

function slotColumns(value: SlotInput) {
  return {
    program_id: value.programId,
    slot_date: value.slotDate,
    start_time: value.startTime,
    end_time: value.endTime,
    capacity: value.capacity,
    office_name: value.officeName,
    what_to_bring: value.whatToBring.length > 0 ? value.whatToBring : null,
  };
}

export async function createSlot(input: SlotInput): Promise<VisitActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can create visit slots.' };

  const parsed = parseSlotInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase
    .from('visit_slots')
    .insert({ ...slotColumns(parsed.value), status: 'open', created_by: actor.id });
  if (error) return failure(error, 'The slot could not be saved.');

  revalidatePath(PAGE);
  return { ok: true, message: 'Slot created.' };
}

// A slot with bookings keeps its program, date, time and office (the database
// refuses the change). Capacity and what to bring can still be edited.
export async function updateSlot(slotId: string, input: SlotInput): Promise<VisitActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can edit visit slots.' };
  if (!UUID.test(slotId)) return { error: 'That slot was not found.' };

  const supabase = createClient();
  const { data: current } = await supabase
    .from('visit_slots')
    .select('slot_date')
    .eq('id', slotId)
    .maybeSingle();
  if (!current) return { error: 'That slot was not found.' };

  // An old slot may be edited without moving its date; only a changed date must not be in the past.
  const unchangedDate = (current as { slot_date: string }).slot_date === input.slotDate;
  const parsed = parseSlotInput(input, unchangedDate ? input.slotDate : undefined);
  if (!parsed.ok) return { error: parsed.reason };

  const { error } = await supabase.from('visit_slots').update(slotColumns(parsed.value)).eq('id', slotId);
  if (error) return failure(error, 'The slot could not be saved.');

  revalidatePath(PAGE);
  return { ok: true, message: 'Slot saved.' };
}

// Close: no new bookings. Cancel: only a slot with nobody booked (the database
// refuses otherwise). A cancelled slot stays cancelled.
export async function setSlotStatus(
  slotId: string,
  status: 'open' | 'closed' | 'cancelled'
): Promise<VisitActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can change a slot.' };
  if (!UUID.test(slotId)) return { error: 'That slot was not found.' };
  if (status !== 'open' && status !== 'closed' && status !== 'cancelled') return { error: 'Choose a valid status.' };

  const supabase = createClient();
  const { data: current } = await supabase.from('visit_slots').select('status').eq('id', slotId).maybeSingle();
  if (!current) return { error: 'That slot was not found.' };
  if ((current as { status: string }).status === 'cancelled') {
    return { error: 'A cancelled slot cannot be changed. Create a new slot instead.' };
  }

  const { error } = await supabase.from('visit_slots').update({ status }).eq('id', slotId);
  if (error) return failure(error, 'The slot could not be updated.');

  revalidatePath(PAGE);
  const word = status === 'open' ? 'reopened' : status === 'closed' ? 'closed' : 'cancelled';
  return { ok: true, message: `Slot ${word}.` };
}

// Put one applicant into a slot, or move them if they already have a visit.
// The optional reason goes into the audit log.
export async function assignSlot(
  applicantId: string,
  slotId: string,
  reason?: string
): Promise<VisitActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can assign visits.' };
  if (!UUID.test(applicantId) || !UUID.test(slotId)) return { error: 'Choose an applicant and a slot.' };

  const note = (reason ?? '').trim();
  if (note.length > MAX_REASON) return { error: `The reason is longer than ${MAX_REASON} characters.` };

  const supabase = createClient();
  const { error } = await supabase.rpc('assign_visit_slot', {
    p_applicant: applicantId,
    p_slot: slotId,
    p_reason: note.length > 0 ? note : null,
  });
  if (error) return failure(error, 'The visit could not be assigned.');

  revalidatePath(PAGE);
  return { ok: true, message: 'Visit assigned. The applicant will see it on their next step card.' };
}

// Fill the earliest open slots of one program with every applicant who has no
// visit, in order of admission date. Reports how many had to be left out.
export async function assignAllUnassigned(programId: string): Promise<VisitActionResult> {
  const actor = await requireStaff();
  if (!actor) return { error: 'Only the Registrar or Admin can assign visits.' };
  if (!UUID.test(programId)) return { error: 'Choose a program.' };

  const supabase = createClient();
  const { data, error } = await supabase.rpc('assign_unassigned_visits', { p_program: programId });
  if (error) return failure(error, 'The visits could not be assigned. Try again.');

  const row = (Array.isArray(data) ? data[0] : data) as { assigned?: number; left_over?: number } | null;
  const assigned = row?.assigned ?? 0;
  const leftOver = row?.left_over ?? 0;

  revalidatePath(PAGE);
  if (assigned === 0 && leftOver === 0) return { ok: true, message: 'Nobody is waiting for a visit.' };
  if (leftOver > 0) {
    return {
      ok: true,
      message: `${assigned} assigned. ${leftOver} still waiting: add slots for this program, then assign again.`,
    };
  }
  return { ok: true, message: `${assigned} assigned.` };
}
