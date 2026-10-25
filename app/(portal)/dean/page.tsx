import { Stack, Title } from '@mantine/core';
import { WorkList } from '@/features/dashboards/WorkList';
import { getCollegeItems } from '@/features/dashboards/queries';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Dean | PLP Enrollment' };

// Counts cover the Dean's own college only (row level security).
export default async function DeanPage() {
  return (
    <Stack gap={spacing.lg}>
      <Title order={3}>Dean</Title>
      <WorkList items={await getCollegeItems('dean')} />
    </Stack>
  );
}
