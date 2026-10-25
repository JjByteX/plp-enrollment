import { Divider, SimpleGrid, Stack } from '@mantine/core';
import { HomeHeading } from '@/features/dashboards/HomeHeading';
import { PipelineBar } from '@/features/dashboards/PipelineBar';
import { SeatFill } from '@/features/dashboards/SeatFill';
import { SectionsAttention } from '@/features/dashboards/SectionsAttention';
import { WorkList } from '@/features/dashboards/WorkList';
import { getCollegeHome } from '@/features/dashboards/queries';
import { todayLabel } from '@/features/dashboards/schema';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Dean | PLP Enrollment' };

// Counts cover the Dean's own college only (row level security). What
// waits on this person comes first, then the sections that wait with how
// complete each one is, how the college's schedules stand and how full they are.
export default async function DeanPage() {
  const home = await getCollegeHome('dean');
  return (
    <Stack gap={spacing.lg}>
      <HomeHeading title="Dean" facts={[todayLabel()]} />
      <WorkList items={home.items} />
      <Divider />
      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing={spacing.xl}>
        <SectionsAttention
          title="Waiting for your sign-off"
          empty="No schedule is waiting for you."
          href="/secretary/schedule?status=pending_dean"
          sections={home.attention}
          total={home.attentionTotal}
        />
        <Stack gap={spacing.lg}>
          <PipelineBar stages={home.pipeline} />
          <Divider />
          <SeatFill seats={home.seats} />
        </Stack>
      </SimpleGrid>
    </Stack>
  );
}
