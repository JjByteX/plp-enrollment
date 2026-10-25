import { Stack, Title } from '@mantine/core';
import { WorkList } from '@/features/dashboards/WorkList';
import { getFinanceItems } from '@/features/dashboards/queries';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Finance | PLP Enrollment' };

export default async function FinancePage() {
  return (
    <Stack gap={spacing.lg}>
      <Title order={3}>Finance</Title>
      <WorkList items={await getFinanceItems()} />
    </Stack>
  );
}
