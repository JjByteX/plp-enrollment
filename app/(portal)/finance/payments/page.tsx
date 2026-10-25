import { PaymentsAdmin } from '@/features/payment/PaymentsAdmin';
import { listPayments, listProgramSettings } from '@/features/payment/queries';
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
  const rows = tab === 'programs' ? [] : await listPayments(tab);
  const programs = tab === 'programs' ? await listProgramSettings() : [];

  return <PaymentsAdmin tab={tab} rows={rows} programs={programs} />;
}
