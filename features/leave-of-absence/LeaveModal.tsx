'use client';

// The leave of absence of one student, in a small centered modal opened from a student row in the
// section details window and from the load window (step 23). The Secretary or the Dean records a
// leave with the first term, how many terms (one or two) and the reason. It waits for the Dean,
// who decides it under Grades, Changes. Students never file a leave themselves.
import { useEffect, useState } from 'react';
import { Divider, Select, Stack, Text, Textarea, Title } from '@mantine/core';
import { FormModal, useFormAction } from '@/components/FormModal';
import { reasonOf } from '@/lib/validate';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { loadLeaveOverview, recordLeave, type LeaveActionResult } from './actions';
import {
  LEAVE_STATUS_LABEL,
  MAX_LEAVE_TERMS_TOTAL,
  MAX_REASON,
  leaveTermKey,
  leaveTermText,
  parseRecordInput,
  startOptions,
  type LeaveOverview,
} from './schema';

export type LeaveStudent = { studentId: string; studentNumber: string; fullName: string };

const TERMS_OPTIONS = [
  { value: '1', label: '1 term' },
  { value: '2', label: '2 terms (one academic year)' },
];

export function LeaveModal({
  student,
  onClose,
  onDone,
}: {
  student: LeaveStudent;
  onClose: () => void;
  onDone: (result: LeaveActionResult) => void;
}) {
  const [overview, setOverview] = useState<LeaveOverview | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [start, setStart] = useState<string | null>(null);
  const [terms, setTerms] = useState<string | null>('1');
  const [reason, setReason] = useState('');
  const { loading, error, run } = useFormAction<LeaveActionResult>(onDone);

  useEffect(() => {
    let current = true;
    void loadLeaveOverview(student.studentId).then((result) => {
      if (!current) return;
      if ('error' in result) setLoadError(result.error);
      else setOverview(result);
    });
    return () => {
      current = false;
    };
  }, [student.studentId]);

  const options = startOptions(overview?.term ?? null);
  const chosen = options.find((option) => leaveTermKey(option) === start) ?? null;
  const parsed = parseRecordInput({
    studentId: student.studentId,
    schoolYear: chosen?.schoolYear,
    semester: chosen?.semester,
    terms: terms === null ? null : Number(terms),
    reason,
  });

  // Why the form cannot be used at all, naming the missing item.
  const blocked =
    overview === null
      ? null
      : !overview.hasEnrollment
        ? 'This student has no enrollment yet, so there is nothing to leave. A new student can withdraw instead.'
        : overview.open
          ? 'This student already has a leave that is not finished.'
          : overview.used >= MAX_LEAVE_TERMS_TOTAL
            ? 'This student has used two academic years of leave.'
            : null;

  function onSubmit() {
    if (!parsed.ok) return;
    void run(() => recordLeave(parsed.value));
  }

  return (
    <FormModal
      title={`Leave of absence, ${student.fullName}`}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={blocked ?? (parsed.ok ? null : reasonOf(parsed))}
      submitLabel="Record leave"
      submitDisabled={!parsed.ok || overview === null || blocked !== null}
    >
      <Text size="sm" c={color.textSecondary}>
        {student.studentNumber}
      </Text>

      {loadError ? (
        <Text size="sm" c={color.error} role="alert">
          {loadError}
        </Text>
      ) : overview === null ? (
        <Text c={color.textSecondary}>Loading.</Text>
      ) : (
        <>
          <Text size="sm" c={color.textSecondary}>
            {overview.used} of {MAX_LEAVE_TERMS_TOTAL} terms of leave used.
          </Text>

          {overview.leaves.length > 0 && (
            <Stack gap={spacing.sm}>
              {overview.leaves.map((leave, index) => (
                <Stack key={leave.id} gap={spacing.xs}>
                  {index > 0 && <Divider />}
                  <Text fw={fontWeight.semibold}>
                    {leaveTermText(leave.startYear, leave.startSemester)}, {leave.terms} {leave.terms === 1 ? 'term' : 'terms'}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {leave.returned && leave.status === 'ended' ? 'Returned' : LEAVE_STATUS_LABEL[leave.status]}. Returns in{' '}
                    {leaveTermText(leave.returnYear, leave.returnSemester)}.
                  </Text>
                  <Text size="sm">{leave.reason}</Text>
                  {leave.status === 'rejected' && leave.decisionNote && (
                    <Text size="sm" c={color.warning}>
                      Not approved: {leave.decisionNote}
                    </Text>
                  )}
                </Stack>
              ))}
              <Divider />
            </Stack>
          )}

          <Title order={4}>New leave</Title>
          {blocked ? (
            <Text c={color.textSecondary}>{blocked}</Text>
          ) : (
            <>
              <Select
                label="First term of the leave"
                placeholder="Choose"
                data={options.map((option) => ({
                  value: leaveTermKey(option),
                  label: leaveTermText(option.schoolYear, option.semester),
                }))}
                value={start}
                onChange={setStart}
                disabled={loading}
                required
              />
              <Select
                label="Length"
                data={TERMS_OPTIONS}
                value={terms}
                onChange={setTerms}
                allowDeselect={false}
                disabled={loading}
                required
              />
              <Textarea
                label="Reason"
                description="Recorded in the audit log. The Dean decides on it."
                value={reason}
                onChange={(event) => setReason(event.currentTarget.value)}
                autosize
                minRows={2}
                maxLength={MAX_REASON}
                disabled={loading}
                required
              />
            </>
          )}
        </>
      )}
    </FormModal>
  );
}
