// features/next-step-card/queries.ts
//
// What the persistent "Your next step" card shows. It is computed from the
// live booking, not from the latest notification, so it is never stale after
// a move. Runs under the signed-in person's session: row level security lets
// an applicant read only their own booking and the slot it points to.
//
// Only Applicants have a next step in this build. Every other role keeps
// "Nothing to do yet" until the dashboards in step 14.
import { createClient } from '@/lib/supabase/server';
import type { CurrentUser } from '@/lib/auth/session';
import { formatSlotDate, windowLabel } from '@/features/visit-scheduling/schema';

export type NextStep =
  | { kind: 'none' }
  | { kind: 'waiting' }
  | { kind: 'visit'; date: string; window: string; office: string; whatToBring: string | null };

type BookingRow = {
  status: 'booked' | 'attended' | 'no_show';
  visit_slots: {
    slot_date: string;
    start_time: string;
    end_time: string;
    office_name: string;
    what_to_bring: string | null;
  } | null;
};

export async function getNextStep(user: CurrentUser): Promise<NextStep> {
  if (user.role !== 'applicant') return { kind: 'none' };

  const supabase = createClient();
  const { data } = await supabase
    .from('visit_bookings')
    .select('status, visit_slots(slot_date, start_time, end_time, office_name, what_to_bring)')
    .maybeSingle();
  const booking = data as unknown as BookingRow | null;

  if (!booking) return { kind: 'waiting' };
  // Attended or no show is handled by step 7; until then there is nothing to show.
  if (booking.status !== 'booked' || !booking.visit_slots) return { kind: 'none' };

  const slot = booking.visit_slots;
  return {
    kind: 'visit',
    date: formatSlotDate(slot.slot_date),
    window: windowLabel(slot.start_time.slice(0, 5), slot.end_time.slice(0, 5)),
    office: slot.office_name,
    whatToBring: slot.what_to_bring,
  };
}
