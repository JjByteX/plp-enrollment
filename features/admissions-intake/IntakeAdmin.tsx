'use client';

import { useState } from 'react';
import { Button, Paper, Stack, Switch, Table, Text } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { resendIntake, setConnectionEnabled, type IntakeActionResult } from './actions';

export type IntakeRow = {
  id: string;
  receivedAt: string;
  applicantRef: string;
  fullName: string;
  programCode: string;
  source: string;
  status: 'accepted' | 'rejected';
  reason: string | null;
  canResend: boolean;
};

export function IntakeAdmin({ enabled, rows }: { enabled: boolean; rows: IntakeRow[] }) {
  const [message, setMessage] = useState<IntakeActionResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  async function run(key: string, action: () => Promise<IntakeActionResult>) {
    setBusy(key);
    setMessage(null);
    setMessage(await action());
    setBusy(null);
  }

  return (
    <Stack gap={spacing.md}>
      <Paper p={padding.card}>
        <Switch
          label="Accept requests from Admissions"
          checked={enabled}
          disabled={busy !== null}
          onChange={(event) => run('toggle', () => setConnectionEnabled(event.currentTarget.checked))}
        />
      </Paper>

      {message && (
        <Text size="sm" c={'error' in message ? color.error : color.success} role="status">
          {'error' in message ? message.error : message.message}
        </Text>
      )}

      <Paper p={padding.card}>
        {rows.length === 0 ? (
          <Text c="dimmed">No requests yet.</Text>
        ) : (
          <Table.ScrollContainer minWidth={840}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Received</Table.Th>
                  <Table.Th>Reference</Table.Th>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Program</Table.Th>
                  <Table.Th>Source</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Reason</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((row) => (
                  <Table.Tr key={row.id}>
                    <Table.Td>{row.receivedAt}</Table.Td>
                    <Table.Td>{row.applicantRef}</Table.Td>
                    <Table.Td>{row.fullName}</Table.Td>
                    <Table.Td>{row.programCode}</Table.Td>
                    <Table.Td>{row.source}</Table.Td>
                    <Table.Td>{row.status === 'accepted' ? 'Accepted' : 'Rejected'}</Table.Td>
                    <Table.Td>{row.reason ?? ''}</Table.Td>
                    <Table.Td>
                      {row.canResend && (
                        <Button
                          variant="default"
                          size="xs"
                          loading={busy === row.id}
                          disabled={busy !== null}
                          onClick={() => run(row.id, () => resendIntake(row.id))}
                        >
                          Resend
                        </Button>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>
    </Stack>
  );
}
