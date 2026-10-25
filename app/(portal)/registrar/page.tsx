import { Divider, Stack, Title } from '@mantine/core';
import { EnrollmentFunnel } from '@/features/dashboards/EnrollmentFunnel';
import { WorkList } from '@/features/dashboards/WorkList';
import { getFunnel, getRegistrarItems } from '@/features/dashboards/queries';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Registrar | PLP Enrollment' };

// What waits first, then the whole enrollment at a glance.
export default async function RegistrarPage() {
  const [items, stages] = await Promise.all([getRegistrarItems(), getFunnel()]);
  return (
    <Stack gap={spacing.lg}>
      <Title order={3}>Registrar</Title>
      <WorkList items={items} />
      <Divider />
      <EnrollmentFunnel stages={stages} />
    </Stack>
  );
}
