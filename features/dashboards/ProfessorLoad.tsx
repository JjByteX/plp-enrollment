'use client';

// The Professor's home: what is on now or next, then the week laid out day by
// day with every subject of their approved schedules, and the class list of
// each (name and student number only) in a centered modal. Read only. A class
// with no time yet sits in its own row at the end. Fewer than 5 students in a
// class list render as a list, 5 or more as a table (ux-ui-guidelines.md).
import { useState } from 'react';
import { Button, Divider, Group, Modal, Stack, Table, Text, UnstyledButton } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { DAY_LABEL, windowLabel } from '@/features/section-scheduling/schema';
import { color, fontFamily, fontSize, fontWeight, padding, radius, spacing } from '@/styles/tokens';
import { nextClass, plural } from './schema';
import type { ClassStudent, LoadRow } from './queries';

const LIST_LIMIT = 5;
const WEEK_DAYS = [1, 2, 3, 4, 5, 6]; // Monday to Saturday; Sunday only when a class is set on it

export function ProfessorLoad({
  rows,
  students,
  clock,
  today,
}: {
  rows: LoadRow[];
  students: ClassStudent[];
  clock: { day: number; minutes: number }; // Manila, read on the server
  today: string; // "Sunday, October 25, 2026"
}) {
  const [open, setOpen] = useState<LoadRow | null>(null);

  const classOf = (row: LoadRow) =>
    students.filter((student) => student.sectionId === row.sectionId && student.subjectCode === row.subjectCode);
  const classList = open ? classOf(open) : [];

  const next = nextClass(rows, clock);
  const sections = new Set(rows.map((row) => row.sectionId)).size;
  const people = new Set(students.map((student) => student.studentNumber)).size;

  const days = rows.some((row) => row.day === 7) ? [...WEEK_DAYS, 7] : WEEK_DAYS;
  const untimed = rows.filter((row) => row.day === null);

  function whenText(row: LoadRow): string {
    const day = row.day === clock.day ? 'Today' : (DAY_LABEL[row.day ?? 0] ?? '');
    return `${day}, ${windowLabel(row.start, row.end)}`;
  }

  function block(row: LoadRow) {
    return (
      <UnstyledButton
        key={row.id}
        className="plp-tile"
        onClick={() => setOpen(row)}
        aria-label={`Class list for ${row.subject}, ${row.section}`}
        style={{
          background: color.accentSubtleBg,
          border: `1px solid ${color.accentSubtleBg}`,
          padding: padding.cell,
          borderRadius: radius.default,
          textAlign: 'left',
        }}
      >
        <Stack gap={spacing.xs}>
          {row.start && (
            <Text size="sm" fw={fontWeight.semibold} c={color.textPrimary}>
              {windowLabel(row.start, row.end)}
            </Text>
          )}
          <Text size="sm" c={color.textPrimary}>
            {row.subject}, {row.title}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {[row.section, row.room].filter(Boolean).join(', ')}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {classOf(row).length} {plural(classOf(row).length, 'student', 'students')}
          </Text>
        </Stack>
      </UnstyledButton>
    );
  }

  return (
    <Stack gap={spacing.lg}>
      <Stack gap={spacing.xs}>
        <PageHeading title="Professor" />
        <Group gap={spacing.md}>
          <Text size="sm" c={color.textSecondary}>
            {today}
          </Text>
          {rows.length > 0 && (
            <Text size="sm" c={color.textSecondary}>
              {rows.length} {plural(rows.length, 'subject', 'subjects')}, {sections} {plural(sections, 'section', 'sections')},{' '}
              {people} {plural(people, 'student', 'students')}
            </Text>
          )}
        </Group>
      </Stack>

      {rows.length === 0 ? (
        <Text c={color.textSecondary}>No subjects are assigned to you yet.</Text>
      ) : (
        <>
          {next && (
            <Stack gap={spacing.sm}>
              <Text fw={fontWeight.semibold}>{next.live ? 'On now' : 'Next class'}</Text>
              <Group justify="space-between" wrap="nowrap" align="flex-start">
                <Stack gap={spacing.xs}>
                  <Text fz={fontSize.lg} fw={fontWeight.semibold} ff={fontFamily.heading}>
                    {next.row.subject}, {next.row.title}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {[whenText(next.row), next.row.room, next.row.section].filter(Boolean).join(', ')}
                  </Text>
                </Stack>
                <Button variant="default" onClick={() => setOpen(next.row)}>
                  Class list
                </Button>
              </Group>
            </Stack>
          )}

          <Divider />

          <Stack gap={spacing.md}>
            <Text fw={fontWeight.semibold}>Week</Text>
            {days.map((day, index) => {
              const dayRows = rows.filter((row) => row.day === day);
              return (
                <Stack key={day} gap={spacing.md}>
                  {index > 0 && <Divider />}
                  <Group align="flex-start" wrap="nowrap" gap={spacing.lg}>
                    <Stack gap={spacing.xs} w={spacing['6xl']} style={{ flex: 'none' }}>
                      <Text fw={fontWeight.semibold}>{DAY_LABEL[day]}</Text>
                      {day === clock.day && (
                        <Text size="sm" c={color.textSecondary}>
                          Today
                        </Text>
                      )}
                    </Stack>
                    {dayRows.length === 0 ? (
                      <Text size="sm" c={color.textSecondary}>
                        Free
                      </Text>
                    ) : (
                      <Group gap={spacing.md} align="stretch">
                        {dayRows.map(block)}
                      </Group>
                    )}
                  </Group>
                </Stack>
              );
            })}
            {untimed.length > 0 && (
              <>
                <Divider />
                <Group align="flex-start" wrap="nowrap" gap={spacing.lg}>
                  <Text fw={fontWeight.semibold} w={spacing['6xl']} style={{ flex: 'none' }}>
                    No time yet
                  </Text>
                  <Group gap={spacing.md} align="stretch">
                    {untimed.map(block)}
                  </Group>
                </Group>
              </>
            )}
          </Stack>
        </>
      )}

      <Modal
        opened={open !== null}
        onClose={() => setOpen(null)}
        title={open ? `${open.subject}, ${open.section}` : ''}
        centered
      >
        {classList.length === 0 ? (
          <Text c={color.textSecondary}>No students are placed in this section yet.</Text>
        ) : classList.length < LIST_LIMIT ? (
          <Stack gap={spacing.sm}>
            {classList.map((student) => (
              <Text key={student.studentNumber}>
                {student.studentNumber}, {student.fullName}
              </Text>
            ))}
          </Stack>
        ) : (
          <Table.ScrollContainer minWidth={360}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Student number</Table.Th>
                  <Table.Th>Name</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {classList.map((student) => (
                  <Table.Tr key={student.studentNumber}>
                    <Table.Td>{student.studentNumber}</Table.Td>
                    <Table.Td>{student.fullName}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Modal>
    </Stack>
  );
}
