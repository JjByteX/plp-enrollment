// features/leave-of-absence/ReadmissionView.tsx
//
// The readmission slip as the returning student reads and prints it (step 23). Presentational
// only: the content comes from my_readmission() in the database. It states the leave and the term
// the student was readmitted to; it does not show the reason for the leave.
import { Divider, Group, Stack, Text, Title } from '@mantine/core';
import { DetailField } from '@/components/DetailField';
import { formatDate } from '@/lib/format';
import { color, spacing } from '@/styles/tokens';
import { leaveTermText, type Readmission } from './schema';

export function ReadmissionView({ slip }: { slip: Readmission }) {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Readmission slip</Title>

      <Group gap={spacing.xl} align="flex-start">
        <Stack gap={spacing.xs}>
          <DetailField label="Student" value={slip.fullName} />
          <Text>{slip.studentNumber}</Text>
        </Stack>
        <Stack gap={spacing.xs}>
          <DetailField label="Program and section" value={slip.programName} />
          <Text>{slip.section ?? slip.programCode}</Text>
        </Stack>
        <Stack gap={spacing.xs}>
          <Text size="sm" c={color.textSecondary}>
            Issued
          </Text>
          <Text>{formatDate(slip.returnedAt)}</Text>
        </Stack>
      </Group>

      <Divider />

      <Stack gap={spacing.xs}>
        <Text>
          Leave of absence: {slip.terms} {slip.terms === 1 ? 'term' : 'terms'}, from the{' '}
          {leaveTermText(slip.startYear, slip.startSemester)}.
        </Text>
        <Text>Readmitted for the {leaveTermText(slip.returnedYear, slip.returnedSemester)}.</Text>
        {slip.approvedBy && (
          <Text size="sm" c={color.textSecondary}>
            Leave approved by {slip.approvedBy}
            {slip.readmittedBy ? `. Load built by ${slip.readmittedBy}.` : '.'}
          </Text>
        )}
      </Stack>

      <Text size="sm" c={color.textSecondary}>
        Your college is preparing your schedule. The assessment slip and the COR follow as usual.
      </Text>
    </Stack>
  );
}
