'use client';

// A small centered dialog that asks for a reason, and a new grade when one is
// needed (grade changes). Used to return grades, to reject a change and to
// propose a change. The button stays disabled until the input is valid.
import { useState } from 'react';
import { Text, TextInput, Textarea } from '@mantine/core';
import { color } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { reasonOf } from '@/lib/validate';
import type { GradingActionResult } from './actions';
import { MAX_REASON, parseReason } from './schema';

// The owner passes the work in through `run`, so this dialog stays free of any one action.
export type RunReason = (reason: string, grade: string) => Promise<GradingActionResult>;

export function ReasonDialog({
  title,
  action,
  withGrade,
  hint,
  run,
  onClose,
  onDone,
}: {
  title: string;
  action: string;
  withGrade?: boolean;
  hint?: string;
  run: RunReason;
  onClose: () => void;
  onDone: (result: GradingActionResult) => void;
}) {
  const [reason, setReason] = useState('');
  const [grade, setGrade] = useState('');
  const { loading, error, run: runAction } = useFormAction(onDone);

  const parsed = parseReason(reason);
  const valid = parsed.ok && (!withGrade || grade.trim() !== '');

  function onSubmit() {
    if (!valid) return;
    void runAction(() => run(reason, grade));
  }

  return (
    <FormModal
      title={title}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel={action}
      submitDisabled={!valid}
    >
      {hint && (
        <Text size="sm" c={color.textSecondary}>
          {hint}
        </Text>
      )}
      {withGrade && (
        <TextInput label="New grade" value={grade} onChange={(event) => setGrade(event.currentTarget.value)} required />
      )}
      <Textarea
        label="Reason"
        value={reason}
        onChange={(event) => setReason(event.currentTarget.value)}
        autosize
        minRows={2}
        maxLength={MAX_REASON}
        required
      />
    </FormModal>
  );
}
