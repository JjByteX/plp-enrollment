'use client';

// components/ReadyIssueList.tsx
//
// The shared body of the Registrar's slips and COR pages. Two tabs:
//   Waiting: students ready for one document. Each row has Issue (records it
//     only) and Issue and print (records it, then opens the print view). Above:
//     Issue all and Issue and print all.
//   Issued: students whose document is already issued this term, each with a
//     Print button for a reprint, and Print all above.
// Issuing happens once; printing can happen any number of times, so they stay
// separate actions. Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). The caller supplies the wording, the actions and the
// print route; the rest lives here once instead of once per document type.
import { useState, type ReactNode } from 'react';
import { Button, Divider, Group, Stack, Table, Tabs, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage, type FormMessageValue } from '@/components/FormMessage';
import { useSectionFilter } from '@/components/SectionFilter';
import type { ReadyStudent } from '@/features/assessment-slip/queries';

const LIST_LIMIT = 5;

function printUrl(printPath: string, students: ReadyStudent[]): string {
  return `${printPath}?ids=${students.map((student) => student.studentId).join(',')}`;
}

function StudentRows({
  students,
  actions,
}: {
  students: ReadyStudent[];
  actions: (student: ReadyStudent, size: 'sm' | 'xs') => ReactNode;
}) {
  if (students.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {students.map((student, index) => (
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
              <Group gap={spacing.sm} wrap="nowrap">
                {actions(student, 'sm')}
              </Group>
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
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
          {students.map((student) => (
            <Table.Tr key={student.studentId}>
              <Table.Td>{student.studentNumber}</Table.Td>
              <Table.Td>{student.fullName}</Table.Td>
              <Table.Td>{student.section}</Table.Td>
              <Table.Td>
                <Group justify="flex-end" gap={spacing.sm} wrap="nowrap">
                  {actions(student, 'xs')}
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

export function ReadyIssueList<R extends FormMessageValue>({
  title,
  emptyText,
  issuedEmptyText,
  ready,
  issued,
  printPath,
  issueOne,
  issueAll,
}: {
  title: string;
  emptyText: string; // shown when no one is waiting
  issuedEmptyText: string; // shown when nothing is issued yet this term
  ready: ReadyStudent[];
  issued: ReadyStudent[];
  printPath: string; // the print view, e.g. /print/cor
  issueOne: (studentId: string) => Promise<R>;
  issueAll: () => Promise<R>;
}) {
  const [tab, setTab] = useState<string | null>('waiting');
  const [message, setMessage] = useState<FormMessageValue | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const sectionFilter = useSectionFilter([...ready, ...issued]);
  const shownReady = sectionFilter.apply(ready);
  const shownIssued = sectionFilter.apply(issued);

  // Issue (and optionally open the print view for `toPrint` afterwards).
  async function run(key: string, action: () => Promise<R>, toPrint?: ReadyStudent[]) {
    if (busy) return;
    setBusy(key);
    setMessage(null);

    // Open the tab now, while the click still counts, so the browser does not
    // block it; point it at the print view only once issuing succeeded.
    const win = toPrint && toPrint.length > 0 ? window.open('', '_blank') : null;
    const result = await action();
    setMessage(result);

    if (toPrint && toPrint.length > 0) {
      if ('error' in result) {
        win?.close();
      } else if (win) {
        win.location.href = printUrl(printPath, toPrint);
      } else {
        setMessage({ message: `${result.message} Your browser blocked the print tab. Print it from the Issued tab.` });
      }
    }
    setBusy(null);
  }

  const idle = busy === null;

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between">
        <PageHeading title={title} parent={{ label: 'Registrar', href: '/registrar' }} />
        {tab === 'issued' ? (
          <Button component="a" href={printUrl(printPath, shownIssued)} target="_blank" disabled={shownIssued.length === 0}>
            Print all
          </Button>
        ) : (
          <Group gap={spacing.sm}>
            <Button
              variant="default"
              loading={busy === 'all'}
              disabled={ready.length === 0 || !idle}
              onClick={() => void run('all', issueAll)}
            >
              Issue all
            </Button>
            <Button
              loading={busy === 'all-print'}
              disabled={ready.length === 0 || !idle}
              onClick={() => void run('all-print', issueAll, ready)}
            >
              Issue and print all
            </Button>
          </Group>
        )}
      </Group>

      <FormMessage message={message} />

      {sectionFilter.control}

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="waiting">Waiting ({shownReady.length})</Tabs.Tab>
          <Tabs.Tab value="issued">Issued ({shownIssued.length})</Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="waiting" pt={spacing.md}>
          {sectionFilter.active && shownReady.length > 0 && (
            <Text size="sm" c={color.textSecondary} pb={spacing.sm}>
              Issue all still covers every section that is waiting.
            </Text>
          )}
          {ready.length === 0 ? (
            <Text c={color.textSecondary}>{emptyText}</Text>
          ) : shownReady.length === 0 ? (
            <Text c={color.textSecondary}>No student in this section is waiting.</Text>
          ) : (
            <StudentRows
              students={shownReady}
              actions={(student, size) => (
                <>
                  <Button
                    variant="default"
                    size={size}
                    loading={busy === student.studentId}
                    disabled={!idle}
                    onClick={() => void run(student.studentId, () => issueOne(student.studentId))}
                  >
                    Issue
                  </Button>
                  <Button
                    size={size}
                    loading={busy === `${student.studentId}-print`}
                    disabled={!idle}
                    onClick={() => void run(`${student.studentId}-print`, () => issueOne(student.studentId), [student])}
                  >
                    Issue and print
                  </Button>
                </>
              )}
            />
          )}
        </Tabs.Panel>

        <Tabs.Panel value="issued" pt={spacing.md}>
          {issued.length === 0 ? (
            <Text c={color.textSecondary}>{issuedEmptyText}</Text>
          ) : shownIssued.length === 0 ? (
            <Text c={color.textSecondary}>No student in this section has been issued.</Text>
          ) : (
            <StudentRows
              students={shownIssued}
              actions={(student, size) => (
                <Button
                  component="a"
                  href={printUrl(printPath, [student])}
                  target="_blank"
                  variant="default"
                  size={size}
                >
                  Print
                </Button>
              )}
            />
          )}
        </Tabs.Panel>
      </Tabs>
    </Stack>
  );
}
