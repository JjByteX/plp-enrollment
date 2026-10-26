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
import { useState } from 'react';
import { Text, TextInput, Textarea } from '@mantine/core';
import { color } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { reasonOf } from '@/lib/validate';
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
  const { loading, error, run } = useFormAction<WithdrawActionResult>(() => {
    setReason('');
    setTyped('');
  });

  const parsed = parseReason(reason);
  const confirmed = confirmMatches(typed, confirmText);

  function close() {
    if (loading) return;
    onClose();
  }

  function onSubmit() {
    if (!parsed.ok || !confirmed) return;
    void run(() => onConfirm(parsed.value));
  }

  return (
    <FormModal
      opened={opened}
      title="Withdraw enrollment"
      onClose={close}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel="Withdraw"
      submitColor={color.error}
      submitDisabled={!parsed.ok || !confirmed}
    >
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
    </FormModal>
  );
}
