'use client';

// The Applicant's and Student's home: where they are in the enrollment steps.
// Enrollment is a linear flow, so it is a stepper, not a sidebar or a grid
// (ux-ui-guidelines.md, layout pattern rules). It opens with how far along the
// person is and what comes after the current step. The details and the actions
// stay in the "Your next step" card of the shell, so nothing is repeated here.
import { Group, Progress, Stack, Stepper, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontFamily, fontSize, fontWeight, layout, spacing } from '@/styles/tokens';
import type { Progress as EnrollmentSteps } from './schema';

export function EnrollmentProgress({ progress }: { progress: EnrollmentSteps }) {
  const total = progress.labels.length;
  const done = Math.min(progress.active, total);
  const complete = progress.active >= total;
  const current = progress.labels[progress.active];
  const after = progress.labels[progress.active + 1];

  return (
    <Stack gap={spacing.lg}>
      <PageHeading title="Progress" />

      <Stack gap={spacing.md}>
        <Group align="baseline" gap={spacing.md}>
          <Text fz={fontSize.display} fw={fontWeight.semibold} ff={fontFamily.heading} lh={1}>
            {done} of {total}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            steps done
          </Text>
        </Group>
        <Progress
          value={(done / total) * 100}
          color={color.accent}
          size={layout.barHeight}
          aria-label={`${done} of ${total} steps done`}
        />
        {!complete && (
          <Text size="sm">
            <Text span fw={fontWeight.semibold}>
              Now: {current}.
            </Text>
            {after ? ` After that: ${after}.` : ''}
          </Text>
        )}
      </Stack>

      <Stepper active={progress.active} orientation="vertical" allowNextStepsSelect={false}>
        {progress.labels.map((label, index) => (
          <Stepper.Step
            key={label}
            label={label}
            description={index < progress.active ? 'Done' : index === progress.active ? 'In progress' : undefined}
          />
        ))}
      </Stepper>
    </Stack>
  );
}
