'use client';

// The Registrar's COR page body: students whose slip is issued, whose payment
// is cleared (or not required) and who have no COR yet. Fewer than 5 rows
// render as a list, 5 or more as a table (ux-ui-guidelines.md). All changes go
// through ./actions.
import { useState } from 'react';
import { Button, Divider, Group, Stack, Table, Text, Title } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { ReadyStudent } from '@/features/assessment-slip/queries';
import { issueAllReadyCors, issueCor, type CorActionResult } from './actions';

const LIST_LIMIT = 5;

export function CorsAdmin({ ready }: { ready: ReadyStudent[] }) {
  const [message, setMessage] = useState<CorActionResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  async function run(key: string, action: () => Promise<CorActionResult>) {
    if (busy) return;
    setBusy(key);
    setMessage(null);
    setMessage(await action());
    setBusy(null);
  }

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between">
        <Title order={3}>Certificates of registration</Title>
        <Button
          loading={busy === 'all'}
          disabled={ready.length === 0 || busy !== null}
          onClick={() => void run('all', issueAllReadyCors)}
        >
          Issue all
        </Button>
      </Group>

      {message && (
        <Text size="sm" c={'error' in message ? color.error : color.success} role="status">
          {'error' in message ? message.error : message.message}
        </Text>
      )}

      <Divider />

      {ready.length === 0 ? (
        <Text c={color.textSecondary}>No COR is waiting.</Text>
      ) : ready.length < LIST_LIMIT ? (
        <Stack gap={spacing.md}>
          {ready.map((student, index) => (
            <Stack key={student.studentId} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between" wrap="nowrap">
                <Stack gap={spacing.xs}>
                  <Text fw={fontWeight.semibold}>
                    {student.studentNumber}, {student.fullName}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {student.section}
                  </Text>
                </Stack>
                <Button
                  variant="default"
                  loading={busy === student.studentId}
                  disabled={busy !== null}
                  onClick={() => void run(student.studentId, () => issueCor(student.studentId))}
                >
                  Issue
                </Button>
              </Group>
            </Stack>
          ))}
        </Stack>
      ) : (
        <Table.ScrollContainer minWidth={720}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Student number</Table.Th>
                <Table.Th>Student</Table.Th>
                <Table.Th>Section</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {ready.map((student) => (
                <Table.Tr key={student.studentId}>
                  <Table.Td>{student.studentNumber}</Table.Td>
                  <Table.Td>{student.fullName}</Table.Td>
                  <Table.Td>{student.section}</Table.Td>
                  <Table.Td>
                    <Group justify="flex-end">
                      <Button
                        variant="default"
                        size="xs"
                        loading={busy === student.studentId}
                        disabled={busy !== null}
                        onClick={() => void run(student.studentId, () => issueCor(student.studentId))}
                      >
                        Issue
                      </Button>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Stack>
  );
}
