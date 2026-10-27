'use client';

// Two lists of leaves of absence (step 23), both built to sit inside the Grades page body.
//   LeaveRequestRows: the leaves waiting for the Dean, on the Dean's Changes tab. Approve, or
//   Reject with a reason. This is the only human decision in a leave.
//   OnLeaveList: the Registrar's read-only list of students on leave with the return term, no control.
// Fewer than 5 rows render as a list, 5 or more as a table (ux-ui-guidelines.md).
import { useState } from 'react';
import { Button, Divider, Group, Stack, Table, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { approveLeave, rejectLeave, type LeaveActionResult } from './actions';
import { LEAVE_STATUS_LABEL, MAX_LEAVE_TERMS_TOTAL, leaveTermText, type LeaveRequest, type OnLeaveStudent } from './schema';
import { ReasonDialog } from '@/features/grading/ReasonModal';

const LIST_LIMIT = 5;

function lengthText(terms: number): string {
  return `${terms} ${terms === 1 ? 'term' : 'terms'}`;
}

export function LeaveRequestRows({
  requests,
  onResult,
}: {
  requests: LeaveRequest[];
  onResult: (result: LeaveActionResult) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<LeaveRequest | null>(null);

  async function approve(request: LeaveRequest) {
    if (busy) return;
    setBusy(request.id);
    const result = await approveLeave(request.id);
    setBusy(null);
    onResult(result);
  }

  return (
    <>
      {requests.map((request, index) => (
        <Stack key={request.id} gap={spacing.sm}>
          {index > 0 && <Divider />}
          <Group justify="space-between" wrap="nowrap" align="flex-start">
            <Stack gap={spacing.xs}>
              <Text fw={fontWeight.semibold}>
                {request.fullName} ({request.studentNumber})
              </Text>
              <Text size="sm" c={color.textSecondary}>
                Leave of absence, {request.programCode}. From the {leaveTermText(request.startYear, request.startSemester)},{' '}
                {lengthText(request.terms)}, returns in {leaveTermText(request.returnYear, request.returnSemester)}.
              </Text>
              <Text size="sm" lineClamp={2}>
                {request.reason}
              </Text>
              <Text size="sm" c={color.textSecondary}>
                {request.usedTerms} of {MAX_LEAVE_TERMS_TOTAL} terms of leave used
                {request.recordedBy ? `, recorded by ${request.recordedBy}` : ''}
              </Text>
            </Stack>
            <Group wrap="nowrap">
              <Button variant="default" disabled={busy !== null} onClick={() => setRejecting(request)}>
                Reject
              </Button>
              <Button
                loading={busy === request.id}
                disabled={busy !== null && busy !== request.id}
                onClick={() => void approve(request)}
              >
                Approve
              </Button>
            </Group>
          </Group>
        </Stack>
      ))}

      {rejecting && (
        <ReasonDialog
          title="Reject leave of absence"
          action="Reject"
          hint="The student stays enrolled. The person who recorded the leave is told."
          run={(reason) => rejectLeave(rejecting.id, reason)}
          onClose={() => setRejecting(null)}
          onDone={(result) => {
            setRejecting(null);
            onResult(result);
          }}
        />
      )}
    </>
  );
}

export function OnLeaveList({ students }: { students: OnLeaveStudent[] }) {
  if (students.length === 0) return <Text c={color.textSecondary}>No student is on leave.</Text>;

  if (students.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {students.map((student, index) => (
          <Stack key={student.id} gap={spacing.xs}>
            {index > 0 && <Divider />}
            <Text fw={fontWeight.semibold}>
              {student.studentNumber}, {student.fullName}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {student.programCode}, {LEAVE_STATUS_LABEL[student.status]}
            </Text>
            <Text size="sm">
              From the {leaveTermText(student.startYear, student.startSemester)}, {lengthText(student.terms)}. Returns in{' '}
              {leaveTermText(student.returnYear, student.returnSemester)}.
            </Text>
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
            <Table.Th>Status</Table.Th>
            <Table.Th>From</Table.Th>
            <Table.Th>Length</Table.Th>
            <Table.Th>Return term</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {students.map((student) => (
            <Table.Tr key={student.id}>
              <Table.Td>
                {student.studentNumber}, {student.fullName}
              </Table.Td>
              <Table.Td>{student.programCode}</Table.Td>
              <Table.Td>{LEAVE_STATUS_LABEL[student.status]}</Table.Td>
              <Table.Td>{leaveTermText(student.startYear, student.startSemester)}</Table.Td>
              <Table.Td>{lengthText(student.terms)}</Table.Td>
              <Table.Td>{leaveTermText(student.returnYear, student.returnSemester)}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
