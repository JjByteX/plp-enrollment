// Where the sections stand in the approval chain (Secretary, Dean, Registrar):
// one bar split by step, with each step's count beside its name. The color is
// never the only signal, the legend carries the numbers. Flat colors from the
// gray and green scales. This is a server component, so it uses the named
// ProgressRoot / ProgressSection exports: dotted names (Progress.Root) cannot
// be read from a client module on the server and crash the page.
import Link from 'next/link';
import { Anchor, Box, Group, ProgressRoot, ProgressSection, Stack, Text } from '@mantine/core';
import { color, fontWeight, gray, green, layout, spacing } from '@/styles/tokens';
import type { ScheduleStatus } from '@/features/section-scheduling/schema';
import type { PipelineStage } from './schema';

const STEP_COLOR: Record<ScheduleStatus, string> = {
  draft: gray[300],
  pending_dean: gray[500],
  dean_signed: green[3],
  approved: green[5],
};

// `href` is the schedules page this role opens; the empty state links there.
export function PipelineBar({ stages, href }: { stages: PipelineStage[]; href?: string }) {
  const total = stages.reduce((sum, stage) => sum + stage.count, 0);

  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>Schedule approvals</Text>
      {total === 0 ? (
        <Text c={color.textSecondary}>
          No sections yet.
          {href && (
            <>
              {' '}
              <Anchor component={Link} href={href} inherit>
                Open schedules
              </Anchor>
            </>
          )}
        </Text>
      ) : (
        <>
          <ProgressRoot size={layout.barHeight} aria-label="Sections by approval step">
            {stages
              .filter((stage) => stage.count > 0)
              .map((stage) => (
                <ProgressSection key={stage.status} value={(stage.count / total) * 100} color={STEP_COLOR[stage.status]} />
              ))}
          </ProgressRoot>
          <Group gap={spacing.lg}>
            {stages.map((stage) => (
              <Group key={stage.status} gap={spacing.sm} wrap="nowrap">
                <Box w={spacing.sm} h={spacing.sm} bg={STEP_COLOR[stage.status]} />
                <Text size="sm">
                  {stage.label}: {stage.count}
                </Text>
              </Group>
            ))}
          </Group>
        </>
      )}
    </Stack>
  );
}
