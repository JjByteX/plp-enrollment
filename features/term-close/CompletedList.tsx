'use client';

// The Registrar's list of students who passed the last semester of the last year of their
// program (step 21). Read only: graduation itself is not built. Fewer than 5 rows render as a
// list, 5 or more as a table (ux-ui-guidelines.md).
import { Divider, Stack, Table, Text } from '@mantine/core';
import { termLabel } from '@/features/cor/schema';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { CompletedStudent } from './schema';

const LIST_LIMIT = 5;

export function CompletedList({ students }: { students: CompletedStudent[] }) {
  if (students.length === 0) return <Text c={color.textSecondary}>No student has completed a program yet.</Text>;

  if (students.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {students.map((student, index) => (
          <Stack key={student.studentId} gap={spacing.xs}>
            {index > 0 && <Divider />}
            <Text fw={fontWeight.semibold}>
              {student.studentNumber}, {student.fullName}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {student.programCode}, completed in {termLabel(student.schoolYear, student.semester)}
            </Text>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={560}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Student</Table.Th>
            <Table.Th>Program</Table.Th>
            <Table.Th>Completed in</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {students.map((student) => (
            <Table.Tr key={student.studentId}>
              <Table.Td>
                {student.studentNumber}, {student.fullName}
              </Table.Td>
              <Table.Td>{student.programCode}</Table.Td>
              <Table.Td>{termLabel(student.schoolYear, student.semester)}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
