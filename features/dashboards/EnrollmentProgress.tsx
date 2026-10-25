'use client';

// The Applicant's and Student's home: where they are in the enrollment steps.
// Enrollment is a linear flow, so it is a stepper, not a sidebar or a grid
// (ux-ui-guidelines.md, layout pattern rules). The details and the actions
// stay in the "Your next step" card of the shell, so nothing is repeated here.
import { Stack, Stepper, Title } from '@mantine/core';
import { spacing } from '@/styles/tokens';
import type { Progress } from './schema';

export function EnrollmentProgress({ progress }: { progress: Progress }) {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Progress</Title>
      <Stepper active={progress.active} orientation="vertical" allowNextStepsSelect={false}>
        {progress.labels.map((label) => (
          <Stepper.Step key={label} label={label} />
        ))}
      </Stepper>
    </Stack>
  );
}
