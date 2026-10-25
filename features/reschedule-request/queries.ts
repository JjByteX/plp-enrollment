// features/reschedule-request/queries.ts
//
// Reads for the Registrar's reschedule requests. They run under the signed-in
// person's session (decision-log.md #10), so row level security applies:
// Registrar and Admin see every request, nobody else sees any.
import { createClient } from '@/lib/supabase/server';
import { first } from '@/features/assessment-slip/queries';
import { listSlots, type SlotRow } from '@/features/visit-scheduling/queries';

export type PendingRequest = {
  requestId: string;
  applicantRef: string;
  fullName: string;
  programId: string;
  programCode: string;
  reason: string;
  requestedAt: string; // ISO timestamp
  currentSlotId: string;
  slotDate: string; // YYYY-MM-DD
  startTime: string; // HH:MM
  endTime: string; // HH:MM
  officeName: string;
};

type RawRequest = {
  id: string;
  reason: string;
  created_at: string;
  visit_bookings: unknown;
};

type RawBooking = {
  slot_id: string;
  applicants: {
    applicant_ref: string;
    program_id: string;
    users: { full_name: string } | null;
    programs: { code: string } | null;
  } | null;
  visit_slots: { slot_date: string; start_time: string; end_time: string; office_name: string } | null;
};

// Requests waiting for an answer, oldest first, with the visit each one is
// about. A request whose booking cannot be read is left out.
export async function listPendingRequests(): Promise<PendingRequest[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('reschedule_requests')
    .select(
      'id, reason, created_at, ' +
        'visit_bookings(slot_id, applicants(applicant_ref, program_id, users(full_name), programs(code)), ' +
        'visit_slots(slot_date, start_time, end_time, office_name))'
    )
    .eq('status', 'pending')
    .order('created_at')
    .order('id');

  return ((data ?? []) as unknown as RawRequest[]).flatMap((row) => {
    const booking = first<RawBooking>(row.visit_bookings);
    if (!booking?.applicants || !booking.visit_slots) return [];
    return [
      {
        requestId: row.id,
        applicantRef: booking.applicants.applicant_ref,
        fullName: booking.applicants.users?.full_name ?? '',
        programId: booking.applicants.program_id,
        programCode: booking.applicants.programs?.code ?? '',
        reason: row.reason,
        requestedAt: row.created_at,
        currentSlotId: booking.slot_id,
        slotDate: booking.visit_slots.slot_date,
        startTime: booking.visit_slots.start_time.slice(0, 5),
        endTime: booking.visit_slots.end_time.slice(0, 5),
        officeName: booking.visit_slots.office_name,
      },
    ];
  });
}

// Open slots with a free seat, not yet over, for the programs of the pending
// requests. The Registrar may pick one when approving; the database still
// checks capacity, program and time.
export async function listOpenSlotsFor(programIds: string[], today: string): Promise<SlotRow[]> {
  if (programIds.length === 0) return [];
  const wanted = new Set(programIds);
  const slots = await listSlots();
  return slots.filter(
    (slot) => wanted.has(slot.programId) && slot.status === 'open' && slot.freeSeats > 0 && slot.slotDate >= today
  );
}
