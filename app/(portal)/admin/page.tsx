import { Divider, SimpleGrid, Stack } from '@mantine/core';
import { EnrollmentFunnel } from '@/features/dashboards/EnrollmentFunnel';
import { HomeHeading } from '@/features/dashboards/HomeHeading';
import { PipelineBar } from '@/features/dashboards/PipelineBar';
import { RecentActivity } from '@/features/dashboards/RecentActivity';
import { VisitCapacity } from '@/features/dashboards/VisitCapacity';
import { WorkList } from '@/features/dashboards/WorkList';
import { getAdminHome, getFunnel, getPipeline } from '@/features/dashboards/queries';
import { todayLabel } from '@/features/dashboards/schema';
import { termLabel } from '@/features/cor/schema';
import { getTerm } from '@/features/content/queries';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Admin | PLP Enrollment' };

// Admin does everything, so this lists every page with what waits on it, then
// the state of the whole enrollment. The term is shown here because no COR can
// be issued until Admin sets it, and only Admin can read it.
export default async function AdminPage() {
  const [{ items, capacity, activity }, stages, pipeline, term] = await Promise.all([
    getAdminHome(),
    getFunnel(),
    getPipeline(),
    getTerm(),
  ]);
  return (
    <Stack gap={spacing.lg}>
      <HomeHeading
        title="Admin"
        facts={[todayLabel(), ...(term ? [termLabel(term.schoolYear, term.semester)] : [])]}
        warning={
          term
            ? undefined
            : {
                text: 'No term is set. No COR can be issued until one is.',
                href: '/admin/content?tab=term',
                linkLabel: 'Set the term',
              }
        }
      />
      <WorkList items={items} />
      <Divider />
      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing={spacing.xl}>
        <EnrollmentFunnel stages={stages} viewerRole="admin" />
        <Stack gap={spacing.lg}>
          <VisitCapacity data={capacity} />
          <Divider />
          <PipelineBar stages={pipeline} href="/registrar/schedules" />
        </Stack>
      </SimpleGrid>
      <Divider />
      <RecentActivity items={activity} />
    </Stack>
  );
}
