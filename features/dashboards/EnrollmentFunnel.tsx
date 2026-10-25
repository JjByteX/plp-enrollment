// How many people reached each enrollment stage. A bar per stage, sized
// against the first stage, with the count beside it. Registrar and Admin only.
import { Group, Progress, Stack, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { FunnelStage } from './schema';

export function EnrollmentFunnel({ stages }: { stages: FunnelStage[] }) {
  const total = stages[0]?.count ?? 0;

  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>Enrollment</Text>
      {total === 0 ? (
        <Text c={color.textSecondary}>No applicants yet.</Text>
      ) : (
        stages.map((stage) => (
          <Stack key={stage.label} gap={spacing.xs}>
            <Group justify="space-between">
              <Text size="sm">{stage.label}</Text>
              <Text size="sm">{stage.count}</Text>
            </Group>
            <Progress value={(stage.count / total) * 100} color={color.accent} aria-label={stage.label} />
          </Stack>
        ))
      )}
    </Stack>
  );
}
