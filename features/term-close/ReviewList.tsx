'use client';

// The needs review list on the Schedules page for the Secretary and the Dean (step 21): students
// of the college who did not pass everything in a closed term and have no section since. Each row
// gives the reason in words. Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). Open builds the student's load (step 22).
import { Button, Divider, Group, Stack, Table, Text } from '@mantine/core';
import { termLabel } from '@/features/cor/schema';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { ReviewStudent } from './schema';

const LIST_LIMIT = 5;

export function ReviewList({
  students,
  onOpen,
}: {
  students: ReviewStudent[];
  onOpen: (student: ReviewStudent) => void;
}) {
  if (students.length === 0) return <Text c={color.textSecondary}>No student needs review.</Text>;

  if (students.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {students.map((student, index) => (
          <Stack key={student.studentId} gap={spacing.xs}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {student.studentNumber}, {student.fullName}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {student.programCode}, year {student.yearLevel}, {termLabel(student.schoolYear, student.semester)}
                </Text>
                <Text size="sm">{student.reason}</Text>
              </Stack>
              <Button variant="default" size="xs" onClick={() => onOpen(student)}>
                Open
              </Button>
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
            <Table.Th>Student</Table.Th>
            <Table.Th>Program</Table.Th>
            <Table.Th>Closed term</Table.Th>
            <Table.Th>Reason</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {students.map((student) => (
            <Table.Tr key={student.studentId}>
              <Table.Td>
                {student.studentNumber}, {student.fullName}
              </Table.Td>
              <Table.Td>
                {student.programCode}, year {student.yearLevel}
              </Table.Td>
              <Table.Td>{termLabel(student.schoolYear, student.semester)}</Table.Td>
              <Table.Td>{student.reason}</Table.Td>
              <Table.Td>
                <Group justify="flex-end">
                  <Button variant="default" size="xs" onClick={() => onOpen(student)}>
                    Open
                  </Button>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
