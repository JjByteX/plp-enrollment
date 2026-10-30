import { PaymentsAdmin } from '@/features/payment/PaymentsAdmin';
import { listPayments, listProgramSettings, type PaymentRow } from '@/features/payment/queries';
import { parseTab } from '@/features/payment/schema';

export const metadata = { title: 'Payments | PLP Enrollment' };

// Finance (and Admin, through the finance area) records payments and sets
// which programs require them. The finance layout already checks the role.
export default async function PaymentsPage({
  searchParams,
}: {
  searchParams: Record<string, string | string[] | undefined>;
}) {
  const tab = parseTab(searchParams.tab);
  // Both lists are read, so the figures above the tabs cover Pending and Cleared whichever is open.
  const none: PaymentRow[] = [];
  const [pending, cleared] =
    tab === 'programs' ? [none, none] : await Promise.all([listPayments('pending'), listPayments('cleared')]);
  const rows = tab === 'pending' ? pending : tab === 'cleared' ? cleared : none;
  const stats =
    tab === 'programs'
      ? null
      : {
          pending: pending.length,
          cleared: cleared.length,
          collected: cleared.reduce((sum, row) => sum + row.amountPaid, 0),
        };
  const programs = tab === 'programs' ? await listProgramSettings() : [];

  return <PaymentsAdmin tab={tab} rows={rows} programs={programs} stats={stats} />;
}
