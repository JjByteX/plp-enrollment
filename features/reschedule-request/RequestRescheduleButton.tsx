'use client';

// The "Request a reschedule" button on the next step card, and the centered
// modal it opens (a focused form that fits one screen). The person gives a
// reason and never picks a date: the Registrar decides (decision-log.md #5).
// The send button stays disabled until the reason is valid, and the reason is
// shown. After sending, the action refreshes the card to its waiting state.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, Stack, Text, Textarea } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { requestReschedule } from './actions';
import { MAX_REASON, parseReason } from './schema';

export function RequestRescheduleButton() {
  const [opened, setOpened] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseReason(reason);

  function close() {
    if (loading) return;
    setOpened(false);
    setError(null);
  }

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || loading) return;
    setLoading(true);
    setError(null);
    const result = await requestReschedule(parsed.value);
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    setOpened(false);
    setReason('');
  }

  return (
    <>
      <Button variant="default" size="xs" onClick={() => setOpened(true)}>
        Request a reschedule
      </Button>
      <Modal
        opened={opened}
        onClose={close}
        title="Request a reschedule"
        padding={padding.modal}
        radius="lg"
        closeOnClickOutside={!loading}
      >
        <form onSubmit={onSubmit}>
          <Stack gap={spacing.md}>
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
            {error && (
              <Text size="sm" c={color.error} role="alert">
                {error}
              </Text>
            )}
            {!parsed.ok && (
              <Text size="sm" c={color.textSecondary}>
                {parsed.reason}
              </Text>
            )}
            <Group justify="space-between">
              <Button variant="default" onClick={close} disabled={loading}>
                Cancel
              </Button>
              <Button type="submit" loading={loading} disabled={!parsed.ok}>
                Send request
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </>
  );
}
