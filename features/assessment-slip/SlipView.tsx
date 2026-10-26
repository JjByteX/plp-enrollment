// features/assessment-slip/SlipView.tsx
//
// The assessment slip as the student reads and prints it. Presentational only:
// the content comes from assessment_slip() in the database.
import {
  Divider,
  Group,
  Stack,
  Table,
  TableScrollContainer,
  TableTbody,
  TableTd,
  TableTh,
  TableThead,
  TableTr,
  Text,
  Title,
} from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { formatDate } from '@/lib/format';
import { DetailField } from '@/components/DetailField';
import { scheduleText, subjectName, totalUnits, type SlipData } from './schema';

export function SlipView({ slip }: { slip: SlipData }) {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Assessment slip</Title>

      <Group gap={spacing.xl} align="flex-start">
        <Stack gap={spacing.xs}>
          <DetailField label="Student" value={slip.fullName} />
          <Text>{slip.studentNumber}</Text>
        </Stack>
        <Stack gap={spacing.xs}>
          <DetailField label="Program and section" value={slip.programName} />
          <Text>{slip.section}</Text>
        </Stack>
        <Stack gap={spacing.xs}>
          <Text size="sm" c={color.textSecondary}>
            Issued
          </Text>
          <Text>{formatDate(slip.issuedAt)}</Text>
        </Stack>
      </Group>

      <Divider />

      <TableScrollContainer minWidth={640}>
        <Table>
          <TableThead>
            <TableTr>
              <TableTh>Subject</TableTh>
              <TableTh>Units</TableTh>
              <TableTh>Professor</TableTh>
              <TableTh>Room</TableTh>
              <TableTh>Schedule</TableTh>
            </TableTr>
          </TableThead>
          <TableTbody>
            {slip.subjects.map((subject) => (
              <TableTr key={`${subject.code}-${subject.meeting}`}>
                <TableTd>
                  {subjectName(subject.code, subject.meeting)}, {subject.title}
                </TableTd>
                <TableTd>{subject.units}</TableTd>
                <TableTd>{subject.professor ?? ''}</TableTd>
                <TableTd>{subject.room ?? ''}</TableTd>
                <TableTd>{scheduleText(subject.day, subject.start, subject.end)}</TableTd>
              </TableTr>
            ))}
          </TableTbody>
        </Table>
      </TableScrollContainer>

      <Text fw={fontWeight.semibold}>Total units: {totalUnits(slip.subjects)}</Text>
      <Text size="sm" c={color.textSecondary}>
        {slip.paymentRequired
          ? 'Payment is required for your program. Finance clears it before the Registrar issues your COR.'
          : 'No payment is required for your program.'}
      </Text>
    </Stack>
  );
}
