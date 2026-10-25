'use client';

// features/withdraw-enrollment/WithdrawModal.tsx
//
// The one confirmation modal for a withdrawal (step 17), used by the profile
// menu (a person withdrawing themselves) and by the Registrar's list (withdrawing
// someone). A focused form that fits one screen: a reason, and a typed
// confirmation so it cannot be done by a stray click. The person types a word;
// the Registrar types the number of the person being withdrawn, so the wrong row
// is caught. The button stays disabled until both are right, and the reason
// check is shown. Nothing is closed or cleared while the request is running.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import type { WithdrawActionResult } from './actions';
import { MAX_REASON, confirmMatches, parseReason } from './schema';

export function WithdrawModal({
  opened,
  onClose,
  description,
  confirmText,
  onConfirm,
}: {
  opened: boolean;
  onClose: () => void;
  description: string; // what is lost, in one or two sentences
  confirmText: string; // what must be typed to confirm
  onConfirm: (reason: string) => Promise<WithdrawActionResult>;
}) {
  const [reason, setReason] = useState('');
  const [typed, setTyped] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseReason(reason);
  const confirmed = confirmMatches(typed, confirmText);

  function close() {
    if (loading) return;
    onClose();
    setError(null);
  }

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || !confirmed || loading) return;
    setLoading(true);
    setError(null);
    const result = await onConfirm(parsed.value);
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onClose();
    setReason('');
    setTyped('');
  }

  return (
    <Modal
      opened={opened}
      onClose={close}
      title="Withdraw enrollment"
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <Text size="sm" c={color.textSecondary}>
            {description}
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
          <TextInput
            label={`Type ${confirmText} to confirm`}
            value={typed}
            onChange={(event) => setTyped(event.currentTarget.value)}
            autoComplete="off"
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
            <Button type="submit" color={color.error} loading={loading} disabled={!parsed.ok || !confirmed}>
              Withdraw
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
