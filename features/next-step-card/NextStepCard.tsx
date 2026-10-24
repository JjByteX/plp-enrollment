// features/next-step-card/NextStepCard.tsx
//
// The persistent "Your next step" card, shown by the portal shell on every
// page. Presentational only: the data comes from ./queries through the layout.
// No reschedule button yet; the reschedule request arrives in step 12.
import { Divider, Stack, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { NextStep } from './queries';

export function NextStepCard({ step }: { step: NextStep }) {
  return (
    <Stack gap={spacing.sm}>
      <Text fw={fontWeight.semibold}>Your next step</Text>

      {step.kind === 'none' && (
        <Text size="sm" c={color.textSecondary}>
          Nothing to do yet.
        </Text>
      )}

      {step.kind === 'waiting' && (
        <Text size="sm" c={color.textSecondary}>
          Waiting for your visit schedule. The Registrar will assign a date and you will see it here.
        </Text>
      )}

      {step.kind === 'student_waiting' && (
        <Stack gap={spacing.sm}>
          <Text size="sm">
            Your documents were received. Your student number is {step.studentNumber}. Your college will prepare your
            schedule and you will see it here.
          </Text>
          {step.openLateItems.length > 0 && (
            <Text size="sm" c={color.textSecondary}>
              Still to submit: {step.openLateItems.join('; ')}.
            </Text>
          )}
        </Stack>
      )}

      {step.kind === 'visit' && (
        <Stack gap={spacing.sm}>
          <Text>
            {step.date}, {step.window}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {step.office}
          </Text>
          {step.whatToBring && (
            <>
              <Divider />
              <Text size="sm" fw={fontWeight.semibold}>
                What to bring
              </Text>
              <Text size="sm" style={{ whiteSpace: 'pre-line' }}>
                {step.whatToBring}
              </Text>
            </>
          )}
        </Stack>
      )}
    </Stack>
  );
}
