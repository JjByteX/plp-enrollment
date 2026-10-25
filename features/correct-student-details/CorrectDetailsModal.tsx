'use client';

// features/correct-student-details/CorrectDetailsModal.tsx
//
// Fixes a student's name or sign-in email after promotion. The fields start
// with what is on record. The button stays disabled until something changed and
// the reason is written. The student is told what changed and why. Nothing is
// closed or cleared while the request is running.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { correctStudentDetails } from './actions';
import { MAX_NAME, cleanName, parseCorrectInput } from './schema';
import { MAX_REASON } from '@/features/reschedule-request/schema';

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
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseCorrectInput({ applicantId, fullName: name, email: mail, reason });
  const changed = cleanName(name) !== fullName || mail.trim().toLowerCase() !== email.toLowerCase();

  function close() {
    if (loading) return;
    onClose();
  }

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || !changed || loading) return;
    setLoading(true);
    setError(null);
    const result = await correctStudentDetails(parsed.value);
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onClose();
  }

  return (
    <Modal
      opened
      onClose={close}
      title="Correct student details"
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
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
          {error && (
            <Text size="sm" c={color.error} role="alert">
              {error}
            </Text>
          )}
          {!error && !parsed.ok && (
            <Text size="sm" c={color.textSecondary}>
              {parsed.reason}
            </Text>
          )}
          {!error && parsed.ok && !changed && (
            <Text size="sm" c={color.textSecondary}>
              Change the name or the email to save.
            </Text>
          )}
          <Group justify="space-between">
            <Button variant="default" onClick={close} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading} disabled={!parsed.ok || !changed}>
              Save correction
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
