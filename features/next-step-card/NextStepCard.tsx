// features/next-step-card/NextStepCard.tsx
//
// The persistent "Your next step" card, shown by the portal shell on every
// page. Presentational only: the data comes from ./queries through the layout.
// An applicant with a booked visit can request a reschedule (step 12); they
// send a reason and never pick the new date.
import { Anchor, Divider, Group, Stack, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { termLabel } from '@/features/cor/schema';
import { RequestRescheduleButton } from '@/features/reschedule-request/RequestRescheduleButton';
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
            Your documents were received. Your student number is {step.studentNumber}.{' '}
            {step.section === null
              ? 'Your college will prepare your schedule and you will see it here.'
              : step.section.approved
                ? `Your schedule for ${step.section.label} is approved.${step.slip ? '' : ' Your next step is the assessment slip from the Registrar.'}`
                : `You are placed in ${step.section.label}. Your college is preparing your schedule.`}
          </Text>
          {step.slip && (
            <Stack gap={spacing.xs}>
              <Text size="sm">
                {step.cor
                  ? `You are officially enrolled for ${termLabel(step.cor.schoolYear, step.cor.semester)}.`
                  : step.slip.paymentRequired && step.payment === 'cleared'
                    ? 'Your payment is cleared. Next, the Registrar issues your COR.'
                    : `Your assessment slip is ready. ${
                        step.slip.paymentRequired
                          ? 'Next, Finance clears your payment, then the Registrar issues your COR.'
                          : 'Next, the Registrar issues your COR.'
                      }`}
              </Text>
              {step.scheduleChanged && !step.cor && (
                <Text size="sm" c={color.textSecondary}>
                  Your schedule changed after your slip was issued. Your COR will show the final schedule.
                </Text>
              )}
              <Anchor href="/slip" size="sm">
                View assessment slip
              </Anchor>
              {step.cor && (
                <Anchor href="/cor" size="sm">
                  View COR
                </Anchor>
              )}
            </Stack>
          )}
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
          <Divider />
          {step.reschedule.status === 'pending' && (
            <Text size="sm" c={color.textSecondary}>
              Your reschedule request is waiting for the Registrar.
            </Text>
          )}
          {step.reschedule.status === 'declined' && (
            <Text size="sm" style={{ whiteSpace: 'pre-line' }}>
              The Registrar declined your reschedule request: {step.reschedule.note}
            </Text>
          )}
          {step.reschedule.status !== 'pending' && (
            <Group>
              <RequestRescheduleButton />
            </Group>
          )}
        </Stack>
      )}
    </Stack>
  );
}
