'use client';

// The "Request a reschedule" button on the next step card, and the centered
// modal it opens (a focused form that fits one screen). The person gives a
// reason and never picks a date: the Registrar decides (decision-log.md #5).
// The send button stays disabled until the reason is valid, and the reason is
// shown. After sending, the action refreshes the card to its waiting state.
import { useState } from 'react';
import { Button, Text, Textarea } from '@mantine/core';
import { color } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { reasonOf } from '@/lib/validate';
import { requestReschedule, type RescheduleActionResult } from './actions';
import { MAX_REASON, parseReason } from './schema';

export function RequestRescheduleButton() {
  const [opened, setOpened] = useState(false);
  const [reason, setReason] = useState('');
  const { loading, error, run } = useFormAction<RescheduleActionResult>(() => {
    setOpened(false);
    setReason('');
  });

  const parsed = parseReason(reason);

  function close() {
    if (loading) return;
    setOpened(false);
  }

  function onSubmit() {
    if (!parsed.ok) return;
    void run(() => requestReschedule(parsed.value));
  }

  return (
    <>
      <Button variant="default" size="xs" onClick={() => setOpened(true)}>
        Request a reschedule
      </Button>
      {opened && (
        <FormModal
          title="Request a reschedule"
          onClose={close}
          onSubmit={onSubmit}
          loading={loading}
          error={error}
          hint={reasonOf(parsed)}
          submitLabel="Send request"
          submitDisabled={!parsed.ok}
        >
          <Text size="sm" c={color.textSecondary}>
            The Registrar reviews your request and chooses the new date.
          </Text>
          <Textarea
            label="Reason"
            value={reason}
            onChange={(event) => setReason(event.currentTarget.value)}
            maxLength={MAX_REASON}
            minRows={3}
            autosize
            required
          />
        </FormModal>
      )}
    </>
  );
}
