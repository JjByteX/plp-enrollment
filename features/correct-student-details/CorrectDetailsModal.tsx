'use client';

// features/correct-student-details/CorrectDetailsModal.tsx
//
// Fixes a student's name or sign-in email after promotion. The fields start
// with what is on record. The button stays disabled until something changed and
// the reason is written. The student is told what changed and why. Nothing is
// closed or cleared while the request is running.
import { useState } from 'react';
import { Text, TextInput, Textarea } from '@mantine/core';
import { color } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { MAX_REASON, reasonOf } from '@/lib/validate';
import { correctStudentDetails, type CorrectActionResult } from './actions';
import { MAX_NAME, cleanName, parseCorrectInput } from './schema';

export function CorrectDetailsModal({
  applicantId,
  studentNumber,
  fullName,
  email,
  onClose,
}: {
  applicantId: string;
  studentNumber: string;
  fullName: string;
  email: string;
  onClose: () => void;
}) {
  const [name, setName] = useState(fullName);
  const [mail, setMail] = useState(email);
  const [reason, setReason] = useState('');
  const { loading, error, run } = useFormAction<CorrectActionResult>(onClose);

  const parsed = parseCorrectInput({ applicantId, fullName: name, email: mail, reason });
  const changed = cleanName(name) !== fullName || mail.trim().toLowerCase() !== email.toLowerCase();

  function close() {
    if (loading) return;
    onClose();
  }

  function onSubmit() {
    if (!parsed.ok || !changed) return;
    void run(() => correctStudentDetails(parsed.value));
  }

  const hint = reasonOf(parsed) ?? (!changed ? 'Change the name or the email to save.' : null);

  return (
    <FormModal
      title="Correct student details"
      onClose={close}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={hint}
      submitLabel="Save correction"
      submitDisabled={!parsed.ok || !changed}
    >
      <Text size="sm" c={color.textSecondary}>
        Student number {studentNumber}. The name shows on the slip, the COR and class lists as soon as you save. A
        slip or COR already printed is not changed. The student number, program and section stay as they are.
      </Text>
      <TextInput
        label="Full name"
        value={name}
        onChange={(event) => setName(event.currentTarget.value)}
        maxLength={MAX_NAME}
        autoComplete="off"
        required
      />
      <TextInput
        label="Email"
        description="The student signs in with this address."
        value={mail}
        onChange={(event) => setMail(event.currentTarget.value)}
        autoComplete="off"
        required
      />
      <Textarea
        label="Reason"
        value={reason}
        onChange={(event) => setReason(event.currentTarget.value)}
        maxLength={MAX_REASON}
        minRows={3}
        autosize
        required
      />
    </FormModal>
  );
}
