'use client';

// The Close term control on the Registrar's Grades page (step 21). One button, disabled with
// the missing section subjects named until every section subject that has students has
// Dean-approved grades. Closing cannot be undone, so it asks first.
import { useState } from 'react';
import { Button, Group, Stack, Text } from '@mantine/core';
import { FormModal, useFormAction } from '@/components/FormModal';
import { termLabel } from '@/features/cor/schema';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { closeTerm, type TermCloseResult } from './actions';
import { closeBlockedReason, type TermStatus } from './schema';

export function CloseTermBar({ status, onDone }: { status: TermStatus; onDone: (result: TermCloseResult) => void }) {
  const [asking, setAsking] = useState(false);
  const blocked = closeBlockedReason(status);
  const term = status.term;

  const { loading, error, run } = useFormAction<TermCloseResult>((result) => {
    setAsking(false);
    onDone(result);
  });

  return (
    <Group justify="space-between" wrap="nowrap" align="flex-start">
      <Stack gap={spacing.xs}>
        <Text fw={fontWeight.semibold}>{term ? termLabel(term.schoolYear, term.semester) : 'No term set'}</Text>
        <Text size="sm" c={color.textSecondary}>
          {blocked ?? `${status.enrolled} ${status.enrolled === 1 ? 'student' : 'students'} enrolled. All grades are approved.`}
        </Text>
      </Stack>
      <Button disabled={blocked !== null} onClick={() => setAsking(true)}>
        Close term
      </Button>

      {asking && term && (
        <FormModal
          title="Close term"
          onClose={() => setAsking(false)}
          onSubmit={() => void run(() => closeTerm())}
          loading={loading}
          error={error}
          submitLabel="Close term"
        >
          <Text size="sm">
            Close {termLabel(term.schoolYear, term.semester)}? Students who passed every subject move to the next term when
            Admin opens it. Anyone with an incomplete, failed or dropped subject goes to the review list of their college.
          </Text>
          <Text size="sm" c={color.textSecondary}>
            This cannot be undone.
          </Text>
        </FormModal>
      )}
    </Group>
  );
}
