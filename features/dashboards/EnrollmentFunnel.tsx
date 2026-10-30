// How many people reached each enrollment stage, led by the one number the
// Registrar wants first: the share of admitted applicants who are enrolled.
// Under it, the place where the most people stall, then a bar per stage sized
// against the first stage. Registrar and Admin only.
import { Group, Progress, Stack, Text } from '@mantine/core';
import { AdminLink } from '@/components/AdminLink';
import type { Role } from '@/lib/auth/roles';
import { color, fontFamily, fontSize, fontWeight, layout, spacing } from '@/styles/tokens';
import { funnelSummary, plural, type FunnelStage } from './schema';

// Admin gets a link to the Admissions page, where applicants arrive from; the Registrar is told to contact an Admin.
export function EnrollmentFunnel({ stages, viewerRole }: { stages: FunnelStage[]; viewerRole: Role }) {
  const summary = funnelSummary(stages);
  const { total, biggestGap } = summary;

  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>Enrollment</Text>
      {total === 0 ? (
        <Text c={color.textSecondary}>
          No applicants yet.
          {' '}
          <AdminLink
            viewerRole={viewerRole}
            href="/admin/admissions"
            label="Check Admissions"
            contact="Contact an Admin if applicants should be here."
          />
        </Text>
      ) : (
        <>
          <Group align="baseline" gap={spacing.md}>
            <Text fz={fontSize.display} fw={fontWeight.semibold} ff={fontFamily.heading} lh={1}>
              {summary.percent}%
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {summary.enrolled} of {total} admitted are enrolled
            </Text>
          </Group>

          {biggestGap && (
            <Text size="sm">
              <Text span fw={fontWeight.semibold}>
                Biggest gap:
              </Text>{' '}
              {biggestGap.count} {plural(biggestGap.count, 'person', 'people')} between {biggestGap.from} and{' '}
              {biggestGap.to}.
            </Text>
          )}

          {stages.map((stage) => (
            <Stack key={stage.label} gap={spacing.xs}>
              <Group justify="space-between">
                <Text size="sm">{stage.label}</Text>
                <Text size="sm" c={color.textSecondary}>
                  {stage.count} ({Math.round((stage.count / total) * 100)}%)
                </Text>
              </Group>
              <Progress
                value={(stage.count / total) * 100}
                color={color.accent}
                size={layout.barHeight}
                aria-label={stage.label}
              />
            </Stack>
          ))}
        </>
      )}
    </Stack>
  );
}
