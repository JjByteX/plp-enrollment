'use client';

// One applicant's checklist. Each document has a Received checkbox and a short
// note. Late items are labelled "Can be submitted later". The primary action,
// Mark documents received, stays disabled and names what is missing until every
// required item is ticked. It asks for a confirmation first, because the
// student number is permanent. After success the modal shows the new number.
import { useState } from 'react';
import { Button, Checkbox, Divider, Group, Modal, Stack, Text, TextInput } from '@mantine/core';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import { markDocumentsReceived, setDocumentReceived } from './actions';
import type { PendingApplicant } from './queries';
import {
  ADMISSION_TYPE_LABEL,
  MAX_NOTE,
  OTHER_DOC_TYPE,
  buildChecklist,
  checklistProgress,
  type ChecklistItem,
  type Requirement,
} from './schema';

type Step = 'checklist' | 'confirm' | 'done';

// Small hint under a document. "Verified in Admissions" means Admissions staff
// approved a scan; the original still has to be received and ticked here.
function describe(item: ChecklistItem, verified: string[]): string | undefined {
  const parts = [];
  if (item.late) parts.push('Can be submitted later');
  if (verified.includes(item.docType)) parts.push('Scan verified in Admissions');
  return parts.length > 0 ? parts.join('. ') : undefined;
}

export function ChecklistModal({
  applicant,
  requirements,
  onClose,
}: {
  applicant: PendingApplicant;
  requirements: Requirement[];
  onClose: () => void;
}) {
  const [step, setStep] = useState<Step>('checklist');
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [studentNumber, setStudentNumber] = useState<string | null>(null);
  const [doneMessage, setDoneMessage] = useState('');

  const items = buildChecklist(applicant.admissionType, requirements, applicant.documents);
  const progress = checklistProgress(items);
  const complete = progress.missing.length === 0;

  const noteOf = (item: ChecklistItem) => notes[item.docType] ?? item.note ?? '';

  async function save(item: ChecklistItem, received: boolean, note: string) {
    if (busy) return;
    setBusy(item.docType);
    setError(null);
    const result = await setDocumentReceived({
      applicantId: applicant.applicantId,
      docType: item.docType,
      received,
      note,
    });
    setBusy(null);
    if ('error' in result) setError(result.error);
  }

  async function promote() {
    if (busy) return;
    setBusy('promote');
    setError(null);
    const result = await markDocumentsReceived(applicant.applicantId);
    setBusy(null);
    if ('error' in result) {
      setError(result.error);
      setStep('checklist');
      return;
    }
    setStudentNumber(result.studentNumber);
    setDoneMessage(result.message);
    setStep('done');
  }

  const title = `${applicant.fullName} (${applicant.applicantRef})`;

  if (step === 'done') {
    return (
      <Modal opened onClose={onClose} title={title} padding={padding.modal} radius="lg" size="md">
        <Stack gap={spacing.md}>
          {studentNumber ? (
            <>
              <Text c={color.textSecondary}>Student number</Text>
              <Text size="lg" fw={fontWeight.semibold}>
                {studentNumber}
              </Text>
            </>
          ) : (
            <Text>{doneMessage}</Text>
          )}
          <Group justify="flex-end">
            <Button onClick={onClose}>Done</Button>
          </Group>
        </Stack>
      </Modal>
    );
  }

  if (step === 'confirm') {
    return (
      <Modal opened onClose={onClose} title="Mark documents received" padding={padding.modal} radius="lg" size="md">
        <Stack gap={spacing.md}>
          <Text>
            This gives {applicant.fullName} a student number and turns the applicant into a student. It cannot be
            undone.
          </Text>
          <Group justify="space-between">
            <Button variant="default" disabled={busy !== null} onClick={() => setStep('checklist')}>
              Back
            </Button>
            <Button loading={busy === 'promote'} onClick={promote}>
              Mark documents received
            </Button>
          </Group>
        </Stack>
      </Modal>
    );
  }

  return (
    <Modal opened onClose={onClose} title={title} padding={padding.modal} radius="lg" size="lg">
      <Stack gap={spacing.md}>
        <Text size="sm" c={color.textSecondary}>
          {applicant.programCode}, {ADMISSION_TYPE_LABEL[applicant.admissionType]}
        </Text>

        {items.length === 0 ? (
          <Text c={color.textSecondary}>No documents are listed for this admission type.</Text>
        ) : (
          items.map((item, index) => {
            const isOther = item.docType === OTHER_DOC_TYPE;
            const note = noteOf(item);
            return (
              <Stack key={item.docType} gap={spacing.sm}>
                {index > 0 && <Divider />}
                <Checkbox
                  label={item.label}
                  description={describe(item, applicant.verifiedDocs)}
                  checked={item.received}
                  disabled={busy !== null || (isOther && !item.received && note.trim().length === 0)}
                  onChange={(event) => save(item, event.currentTarget.checked, note)}
                />
                {(item.received || isOther) && (
                  <TextInput
                    aria-label={`Note for ${item.label}`}
                    placeholder={isOther ? 'What is it? (required)' : 'Note (optional)'}
                    maxLength={MAX_NOTE}
                    value={note}
                    onChange={(event) => {
                      const value = event.currentTarget.value;
                      setNotes((current) => ({ ...current, [item.docType]: value }));
                    }}
                    onBlur={() => {
                      if (item.received && note !== (item.note ?? '')) void save(item, true, note);
                    }}
                    disabled={busy !== null}
                  />
                )}
              </Stack>
            );
          })
        )}

        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}

        <Divider />

        {!complete && (
          <Text size="sm" c={color.textSecondary}>
            Missing: {progress.missing.join('; ')}
          </Text>
        )}
        <Group justify="space-between">
          <Button variant="default" onClick={onClose}>
            Close
          </Button>
          <Button disabled={!complete || busy !== null} onClick={() => setStep('confirm')}>
            Mark documents received
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
