// Where the sections stand in the approval chain (Secretary, Dean, Registrar):
// one bar split by step, with each step's count beside its name. The color is
// never the only signal, the legend carries the numbers. Flat colors from the
// gray and green scales.
import { Box, Group, Progress, Stack, Text } from '@mantine/core';
import { color, fontWeight, gray, green, layout, spacing } from '@/styles/tokens';
import type { ScheduleStatus } from '@/features/section-scheduling/schema';
import type { PipelineStage } from './schema';

const STEP_COLOR: Record<ScheduleStatus, string> = {
  draft: gray[300],
  pending_dean: gray[500],
  dean_signed: green[3],
  approved: green[5],
};

export function PipelineBar({ stages }: { stages: PipelineStage[] }) {
  const total = stages.reduce((sum, stage) => sum + stage.count, 0);

  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>Schedule approvals</Text>
      {total === 0 ? (
        <Text c={color.textSecondary}>No sections yet.</Text>
      ) : (
        <>
          <Progress.Root size={layout.barHeight} aria-label="Sections by approval step">
            {stages
              .filter((stage) => stage.count > 0)
              .map((stage) => (
                <Progress.Section key={stage.status} value={(stage.count / total) * 100} color={STEP_COLOR[stage.status]} />
              ))}
          </Progress.Root>
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
