'use client';

// components/ReadyIssueList.tsx
//
// The shared body of the Registrar's slips and COR pages: a list of students
// ready for one document, each with an Issue button, and an Issue all button
// above. Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). The caller supplies the title, the empty-state text
// and the two actions; everything else (busy state, the message line, the
// list/table switch) lives here once instead of once per document type.
import { useState } from 'react';
import { Button, Divider, Group, Stack, Table, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage, type FormMessageValue } from '@/components/FormMessage';
import type { ReadyStudent } from '@/features/assessment-slip/queries';

const LIST_LIMIT = 5;

export function ReadyIssueList<R extends FormMessageValue>({
  title,
  emptyText,
  ready,
  issueOne,
  issueAll,
}: {
  title: string;
  emptyText: string; // shown when no one is waiting
  ready: ReadyStudent[];
  issueOne: (studentId: string) => Promise<R>;
  issueAll: () => Promise<R>;
}) {
  const [message, setMessage] = useState<R | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  async function run(key: string, action: () => Promise<R>) {
    if (busy) return;
    setBusy(key);
    setMessage(null);
    setMessage(await action());
    setBusy(null);
  }

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between">
        <PageHeading title={title} parent={{ label: 'Registrar', href: '/registrar' }} />
        <Button
          loading={busy === 'all'}
          disabled={ready.length === 0 || busy !== null}
          onClick={() => void run('all', issueAll)}
        >
          Issue all
        </Button>
      </Group>

      <FormMessage message={message} />

      <Divider />

      {ready.length === 0 ? (
        <Text c={color.textSecondary}>{emptyText}</Text>
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
                  onClick={() => void run(student.studentId, () => issueOne(student.studentId))}
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
                        onClick={() => void run(student.studentId, () => issueOne(student.studentId))}
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
