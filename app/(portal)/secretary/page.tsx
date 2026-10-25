import { Stack, Title } from '@mantine/core';
import { WorkList } from '@/features/dashboards/WorkList';
import { getCollegeItems } from '@/features/dashboards/queries';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'College Secretary | PLP Enrollment' };

// Counts cover the Secretary's own college only (row level security).
export default async function SecretaryPage() {
  return (
    <Stack gap={spacing.lg}>
      <Title order={3}>College Secretary</Title>
      <WorkList items={await getCollegeItems('secretary')} />
    </Stack>
  );
}
