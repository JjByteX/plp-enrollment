import { Divider, Stack, Title } from '@mantine/core';
import { EnrollmentFunnel } from '@/features/dashboards/EnrollmentFunnel';
import { WorkList } from '@/features/dashboards/WorkList';
import { getAdminItems, getFunnel } from '@/features/dashboards/queries';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Admin | PLP Enrollment' };

// Admin does everything, so this lists every page with what waits on it.
export default async function AdminPage() {
  const [items, stages] = await Promise.all([getAdminItems(), getFunnel()]);
  return (
    <Stack gap={spacing.lg}>
      <Title order={3}>Admin</Title>
      <WorkList items={items} />
      <Divider />
      <EnrollmentFunnel stages={stages} />
    </Stack>
  );
}
