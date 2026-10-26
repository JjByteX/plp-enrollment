'use client';

// The credits of one student, in a small centered modal opened from a student row in the
// section details window (step 20). The Dean or the Secretary records a credit for a subject
// from the transferee's earlier schooling, with the reason naming the line of the TOR. It
// waits for the Registrar, who approves it under Grades, Changes. Only an approved credit
// counts as a pass.
import { useEffect, useState } from 'react';
import { Divider, Select, Stack, Text, Textarea, Title } from '@mantine/core';
import { FormModal, useFormAction } from '@/components/FormModal';
import { reasonOf } from '@/lib/validate';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { loadCreditOverview, recordCredit, type PrerequisiteActionResult } from './actions';
import { CREDIT_STATUS_LABEL, MAX_REASON, parseCreditInput, type CreditOverview } from './schema';

export type CreditStudent = { studentId: string; studentNumber: string; fullName: string };

export function CreditsModal({
  student,
  onClose,
  onDone,
}: {
  student: CreditStudent;
  onClose: () => void;
  onDone: (result: PrerequisiteActionResult) => void;
}) {
  const [overview, setOverview] = useState<CreditOverview | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [subjectId, setSubjectId] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const { loading, error, run } = useFormAction<PrerequisiteActionResult>(onDone);

  useEffect(() => {
    let current = true;
    void loadCreditOverview(student.studentId).then((result) => {
      if (!current) return;
      if ('error' in result) setLoadError(result.error);
      else setOverview(result);
    });
    return () => {
      current = false;
    };
  }, [student.studentId]);

  const parsed = parseCreditInput({ studentId: student.studentId, subjectId, reason });
  const options = (overview?.options ?? []).map((item) => ({ value: item.subjectId, label: `${item.code}, ${item.title}` }));

  function onSubmit() {
    if (!parsed.ok) return;
    void run(() => recordCredit(parsed.value));
  }

  return (
    <FormModal
      title={`Credits, ${student.fullName}`}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={parsed.ok ? null : reasonOf(parsed)}
      submitLabel="Record credit"
      submitDisabled={!parsed.ok || overview === null}
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
          {overview.credits.length === 0 ? (
            <Text c={color.textSecondary}>No credit has been recorded for this student.</Text>
          ) : (
            <Stack gap={spacing.sm}>
              {overview.credits.map((credit, index) => (
                <Stack key={credit.id} gap={spacing.xs}>
                  {index > 0 && <Divider />}
                  <Text fw={fontWeight.semibold}>
                    {credit.code}, {credit.title}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {CREDIT_STATUS_LABEL[credit.status]}
                    {credit.recordedBy ? `, recorded by ${credit.recordedBy}` : ''}
                  </Text>
                  <Text size="sm">{credit.reason}</Text>
                  {credit.status === 'rejected' && credit.rejectedReason && (
                    <Text size="sm" c={color.warning}>
                      Rejected: {credit.rejectedReason}
                    </Text>
                  )}
                </Stack>
              ))}
            </Stack>
          )}

          <Divider />
          <Title order={4}>New credit</Title>
          {options.length === 0 ? (
            <Text c={color.textSecondary}>Every subject of this program is already passed, credited or waiting.</Text>
          ) : (
            <>
              <Select
                label="Subject"
                placeholder="Choose"
                data={options}
                value={subjectId}
                onChange={setSubjectId}
                searchable
                disabled={loading}
                required
              />
              <Textarea
                label="Reason"
                description="Name the line of the transferee's TOR that shows this subject"
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
