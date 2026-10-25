// features/reschedule-mass/queries.ts
//
// What a mass reschedule would move. Reads run under the signed-in person's
// session (decision-log.md #10), so row level security applies: Registrar and
// Admin see every booking, nobody else sees any.
import { listSlots } from '@/features/visit-scheduling/queries';

export type BookedVisit = {
  bookingId: string;
  applicantId: string;
  applicantRef: string;
  fullName: string;
  programId: string;
  programCode: string;
  officeName: string;
};

// Visits still marked booked in a slot on one date. Attended and no show
// visits are not listed: a reschedule never moves them.
export async function listBookedOn(date: string): Promise<BookedVisit[]> {
  const slots = await listSlots({ date });
  return slots.flatMap((slot) =>
    slot.bookings
      .filter((booking) => booking.status === 'booked')
      .map((booking) => ({
        bookingId: booking.bookingId,
        applicantId: booking.applicantId,
        applicantRef: booking.applicantRef,
        fullName: booking.fullName,
        programId: slot.programId,
        programCode: slot.programCode,
        officeName: slot.officeName,
      }))
  );
}
