// features/cor/CorView.tsx
//
// The Certificate of Registration as the student reads and prints it, laid
// out like PLP's own COR: header, student block, class schedule, payment, the
// certification, signatures and the "officially enrolled" stamp. Presentational
// only: the content comes from certificate_of_registration() in the database.
// There is no fee schedule, so the payment block shows what Finance recorded.
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
import { formatPeso } from '@/features/payment/schema';
import {
  ADMISSION_TYPE_LABEL,
  formatIssuedDate,
  scheduleText,
  subjectName,
  termLabel,
  totalUnits,
  yearLabel,
  type CorData,
} from './schema';

const HEADER_LINES = [
  'City Government of Pasig',
  'Pamantasan ng Lungsod ng Pasig',
  'Office of the University Registrar',
  'Alkalde Jose St. Kapasigan, Pasig City, Philippines 1600',
];
const CERTIFICATION =
  'This is to certify that the student whose name appears on this document is officially enrolled this term with the subject load listed above.';
const NOTICE =
  'Notice to all students: present this certificate of registration for any claim or transaction that you engage in within the University.';

function Field({ label, value }: { label: string; value: string }) {
  return (
    <Stack gap={spacing.xs}>
      <Text size="sm" c={color.textSecondary}>
        {label}
      </Text>
      <Text fw={fontWeight.semibold}>{value}</Text>
    </Stack>
  );
}

export function CorView({ cor }: { cor: CorData }) {
  const registrarCaption = cor.issuedByRole === 'admin' ? 'Admin' : 'University Registrar';

  return (
    <Stack gap={spacing.md}>
      <Stack gap={spacing.xs} align="center">
        {HEADER_LINES.map((line, index) => (
          <Text key={line} fw={index === 1 ? fontWeight.semibold : fontWeight.regular} ta="center">
            {line}
          </Text>
        ))}
      </Stack>

      <Title order={3} ta="center">
        Certificate of registration
      </Title>

      <Group gap={spacing.xl} align="flex-start">
        <Stack gap={spacing.md}>
          <Field label="Student number" value={cor.studentNumber} />
          <Field label="Student name" value={cor.fullName} />
          <Field label="Course" value={cor.programName} />
          <Field label="Department" value={cor.collegeName} />
        </Stack>
        <Stack gap={spacing.md}>
          <Field label="Enrollment date" value={formatIssuedDate(cor.issuedAt)} />
          <Field label="School year and semester" value={termLabel(cor.schoolYear, cor.semester)} />
          <Field label="Year level" value={yearLabel(cor.yearLevel)} />
          <Field label="Student type" value={ADMISSION_TYPE_LABEL[cor.admissionType]} />
        </Stack>
      </Group>

      <Divider />

      <Title order={4}>Class schedule</Title>
      <TableScrollContainer minWidth={720}>
        <Table>
          <TableThead>
            <TableTr>
              <TableTh>Subject</TableTh>
              <TableTh>Description</TableTh>
              <TableTh>Section</TableTh>
              <TableTh>Units</TableTh>
              <TableTh>Room</TableTh>
              <TableTh>Schedule</TableTh>
            </TableTr>
          </TableThead>
          <TableTbody>
            {cor.subjects.map((subject) => (
              <TableTr key={`${subject.code}-${subject.meeting}`}>
                <TableTd>{subjectName(subject.code, subject.meeting)}</TableTd>
                <TableTd>{subject.title}</TableTd>
                <TableTd>{cor.section}</TableTd>
                <TableTd>{Number(subject.units).toFixed(2)}</TableTd>
                <TableTd>{subject.room ?? ''}</TableTd>
                <TableTd>{scheduleText(subject.day, subject.start, subject.end)}</TableTd>
              </TableTr>
            ))}
          </TableTbody>
        </Table>
      </TableScrollContainer>
      <Text fw={fontWeight.semibold}>Total units: {totalUnits(cor.subjects).toFixed(2)}</Text>

      <Divider />

      <Title order={4}>Payment</Title>
      {cor.paymentRequired && cor.amountPaid !== null ? (
        <Group gap={spacing.xl} align="flex-start">
          <Field label="Amount due" value={formatPeso(cor.amountDue ?? 0)} />
          <Field label="Amount paid" value={formatPeso(cor.amountPaid)} />
          {cor.receiptNo && <Field label="Receipt number" value={cor.receiptNo} />}
        </Group>
      ) : (
        <Text size="sm" c={color.textSecondary}>
          No payment was required for your program.
        </Text>
      )}

      <Divider />

      <Text>{CERTIFICATION}</Text>

      <Group justify="space-between" align="flex-end" mt={spacing.xl}>
        <Stack gap={spacing.xs} align="center">
          <Text fw={fontWeight.semibold}>{cor.fullName}</Text>
          <Divider w="100%" />
          <Text size="sm" c={color.textSecondary}>
            Student signature
          </Text>
        </Stack>
        <Stack gap={spacing.xs} align="center">
          <Text fw={fontWeight.semibold}>{cor.issuedByName}</Text>
          <Divider w="100%" />
          <Text size="sm" c={color.textSecondary}>
            {registrarCaption}
          </Text>
        </Stack>
      </Group>

      <Stack gap={spacing.xs} align="center">
        <Title order={3}>Officially enrolled</Title>
        <Text fw={fontWeight.semibold}>{termLabel(cor.schoolYear, cor.semester)}</Text>
      </Stack>
      <Text size="sm" c={color.textSecondary} ta="center">
        {NOTICE}
      </Text>
    </Stack>
  );
}
