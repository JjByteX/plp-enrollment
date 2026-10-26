'use client';

// A small centered dialog that asks for a reason, and a new grade when one is
// needed (grade changes). Used to return grades, to reject a change and to
// propose a change. The button stays disabled until the input is valid.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import type { GradingActionResult } from './actions';
import { parseReason } from './schema';

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
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseReason(reason);
  const valid = parsed.ok && (!withGrade || grade.trim() !== '');

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || loading) return;
    setLoading(true);
    setError(null);
    const result = await run(reason, grade);
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onDone(result);
  }

  return (
    <Modal opened onClose={onClose} title={title} padding={padding.modal} radius="lg" closeOnClickOutside={!loading}>
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          {hint && (
            <Text size="sm" c={color.textSecondary}>
              {hint}
            </Text>
          )}
          {withGrade && <TextInput label="New grade" value={grade} onChange={(event) => setGrade(event.currentTarget.value)} required />}
          <Textarea label="Reason" value={reason} onChange={(event) => setReason(event.currentTarget.value)} autosize minRows={2} maxLength={500} required />
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
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading} disabled={!valid}>
              {action}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
