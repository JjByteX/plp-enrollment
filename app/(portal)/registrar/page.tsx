import { Divider, SimpleGrid, Stack } from '@mantine/core';
import { EnrollmentFunnel } from '@/features/dashboards/EnrollmentFunnel';
import { HomeHeading } from '@/features/dashboards/HomeHeading';
import { PipelineBar } from '@/features/dashboards/PipelineBar';
import { VisitCapacity } from '@/features/dashboards/VisitCapacity';
import { WorkList } from '@/features/dashboards/WorkList';
import { getFunnel, getPipeline, getRegistrarHome } from '@/features/dashboards/queries';
import { todayLabel } from '@/features/dashboards/schema';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Registrar | PLP Enrollment' };

// What waits first, then the whole enrollment at a glance: how far the
// admitted applicants have come, whether the visit seats cover the people
// still without a date, and where the schedules stand in the approval chain.
export default async function RegistrarPage() {
  const [{ items, capacity }, stages, pipeline] = await Promise.all([getRegistrarHome(), getFunnel(), getPipeline()]);
  return (
    <Stack gap={spacing.lg}>
      <HomeHeading title="Registrar" facts={[todayLabel()]} />
      <WorkList items={items} />
      <Divider />
      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing={spacing.xl}>
        <EnrollmentFunnel stages={stages} viewerRole="registrar" />
        <Stack gap={spacing.lg}>
          <VisitCapacity data={capacity} />
          <Divider />
          <PipelineBar stages={pipeline} href="/registrar/schedules" />
        </Stack>
      </SimpleGrid>
    </Stack>
  );
}
