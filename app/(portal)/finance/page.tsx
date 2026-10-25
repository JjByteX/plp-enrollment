import { Divider, Stack } from '@mantine/core';
import { FinanceSummary } from '@/features/dashboards/FinanceSummary';
import { HomeHeading } from '@/features/dashboards/HomeHeading';
import { WorkList } from '@/features/dashboards/WorkList';
import { getFinanceHome } from '@/features/dashboards/queries';
import { todayLabel } from '@/features/dashboards/schema';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Finance | PLP Enrollment' };

// What waits first, then the record: what has been collected, who is next in
// line to be recorded and the payments that cleared last.
export default async function FinancePage() {
  const home = await getFinanceHome();
  return (
    <Stack gap={spacing.lg}>
      <HomeHeading title="Finance" facts={[todayLabel()]} />
      <WorkList items={home.items} />
      <Divider />
      <FinanceSummary home={home} />
    </Stack>
  );
}
