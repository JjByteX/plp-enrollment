// features/assessment-slip/SlipView.tsx
//
// The assessment slip as the student reads and prints it. Presentational only:
// the content comes from assessment_slip() in the database.
import { Divider, Group, Stack, Table, Text, Title } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { formatIssuedDate, scheduleText, subjectName, totalUnits, type SlipData } from './schema';

export function SlipView({ slip }: { slip: SlipData }) {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Assessment slip</Title>

      <Group gap={spacing.xl} align="flex-start">
        <Stack gap={spacing.xs}>
          <Text size="sm" c={color.textSecondary}>
            Student
          </Text>
          <Text fw={fontWeight.semibold}>{slip.fullName}</Text>
          <Text>{slip.studentNumber}</Text>
        </Stack>
        <Stack gap={spacing.xs}>
          <Text size="sm" c={color.textSecondary}>
            Program and section
          </Text>
          <Text fw={fontWeight.semibold}>{slip.programName}</Text>
          <Text>{slip.section}</Text>
        </Stack>
        <Stack gap={spacing.xs}>
          <Text size="sm" c={color.textSecondary}>
            Issued
          </Text>
          <Text>{formatIssuedDate(slip.issuedAt)}</Text>
        </Stack>
      </Group>

      <Divider />

      <Table.ScrollContainer minWidth={640}>
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Subject</Table.Th>
              <Table.Th>Units</Table.Th>
              <Table.Th>Professor</Table.Th>
              <Table.Th>Room</Table.Th>
              <Table.Th>Schedule</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {slip.subjects.map((subject) => (
              <Table.Tr key={`${subject.code}-${subject.meeting}`}>
                <Table.Td>
                  {subjectName(subject.code, subject.meeting)}, {subject.title}
                </Table.Td>
                <Table.Td>{subject.units}</Table.Td>
                <Table.Td>{subject.professor ?? ''}</Table.Td>
                <Table.Td>{subject.room ?? ''}</Table.Td>
                <Table.Td>{scheduleText(subject.day, subject.start, subject.end)}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>

      <Text fw={fontWeight.semibold}>Total units: {totalUnits(slip.subjects)}</Text>
      <Text size="sm" c={color.textSecondary}>
        {slip.paymentRequired
          ? 'Payment is required for your program. Finance clears it before the Registrar issues your COR.'
          : 'No payment is required for your program.'}
      </Text>
    </Stack>
  );
}
