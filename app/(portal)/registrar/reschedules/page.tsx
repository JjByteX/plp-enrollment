import { ReschedulesAdmin } from '@/features/reschedule-request/ReschedulesAdmin';
import { listOpenSlotsFor, listPendingRequests } from '@/features/reschedule-request/queries';
import { listBookedOn } from '@/features/reschedule-mass/queries';
import { isRealDate, manilaToday } from '@/features/reschedule-mass/schema';

export const metadata = { title: 'Reschedules | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) answers reschedule
// requests and sets a mass reschedule. The registrar layout already checks the
// role. The mass tab keeps its date in the URL so the server can count the
// visits booked on it.
export default async function ReschedulesPage({
  searchParams,
}: {
  searchParams: { tab?: string; date?: string };
}) {
  const tab = searchParams.tab === 'mass' ? 'mass' : 'requests';
  const date = tab === 'mass' && searchParams.date && isRealDate(searchParams.date) ? searchParams.date : null;
  const today = manilaToday();

  const [requests, booked] = await Promise.all([
    listPendingRequests(),
    date ? listBookedOn(date) : Promise.resolve([]),
  ]);
  // Open slots are only needed to pick one when approving a request.
  const openSlots =
    tab === 'requests'
      ? await listOpenSlotsFor(Array.from(new Set(requests.map((request) => request.programId))), today)
      : [];

  return (
    <ReschedulesAdmin tab={tab} requests={requests} openSlots={openSlots} date={date} today={today} booked={booked} />
  );
}
