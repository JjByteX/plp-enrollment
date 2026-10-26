'use client';

// The Registrar answers one request, in a centered modal. Approve moves the
// visit to the chosen slot, or to the next open slot on another date when none
// is chosen. Decline needs a note, which the person is shown. Decline stays
// disabled until the note is written, and the note field says so.
import { useState } from 'react';
import { Button, Group, Modal, Select, Stack, Text, Textarea } from '@mantine/core';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import { formatDate } from '@/lib/format';
import type { SlotRow } from '@/features/visit-scheduling/queries';
import { slotOptionLabel } from '@/features/visit-scheduling/SlotDetailsModal';
import { decideReschedule, type RescheduleActionResult } from './actions';
import type { PendingRequest } from './queries';
import { MAX_REASON, formatSlotDate, parseDecisionInput, windowLabel } from './schema';

export function DecideRescheduleModal({
  request,
  slots,
  onClose,
  onDone,
}: {
  request: PendingRequest;
  slots: SlotRow[]; // open slots of the same program with a free seat, not the current one
  onClose: () => void;
  onDone: (result: RescheduleActionResult) => void;
}) {
  const [slotId, setSlotId] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState<'approve' | 'decline' | null>(null);
  const [error, setError] = useState<string | null>(null);

  const options = slots.map((slot) => ({ value: slot.id, label: slotOptionLabel(slot) }));

  async function answer(approve: boolean) {
    if (busy) return;
    const parsed = parseDecisionInput({
      requestId: request.requestId,
      approve,
      slotId: approve ? slotId : null,
      note,
    });
    if (!parsed.ok) {
      setError(parsed.reason);
      return;
    }
    setBusy(approve ? 'approve' : 'decline');
    setError(null);
    const result = await decideReschedule(parsed.value);
    setBusy(null);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onDone(result);
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title="Reschedule request"
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={busy === null}
    >
      <Stack gap={spacing.md}>
        <Stack gap={spacing.xs}>
          <Text fw={fontWeight.semibold}>
            {request.fullName} ({request.applicantRef})
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {request.programCode}, {formatSlotDate(request.slotDate)}, {windowLabel(request.startTime, request.endTime)},{' '}
            {request.officeName}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            Sent {formatDate(request.requestedAt)}
          </Text>
        </Stack>
        <Text size="sm" style={{ whiteSpace: 'pre-line' }}>
          {request.reason}
        </Text>
        <Select
          label="Move to"
          placeholder="Next open slot on another date"
          data={options}
          value={slotId}
          onChange={setSlotId}
          disabled={busy !== null}
          clearable
          searchable
        />
        <Textarea
          label="Note"
          description="Optional when approving. Required to decline, and the person sees it."
          value={note}
          onChange={(event) => setNote(event.currentTarget.value)}
          maxLength={MAX_REASON}
          minRows={2}
          autosize
          disabled={busy !== null}
        />
        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}
        <Group justify="space-between">
          <Button variant="default" onClick={onClose} disabled={busy !== null}>
            Cancel
          </Button>
          <Group gap={spacing.sm}>
            <Button
              variant="default"
              loading={busy === 'decline'}
              disabled={note.trim().length === 0 || busy !== null}
              onClick={() => void answer(false)}
            >
              Decline
            </Button>
            <Button loading={busy === 'approve'} disabled={busy !== null} onClick={() => void answer(true)}>
              Approve
            </Button>
          </Group>
        </Group>
      </Stack>
    </Modal>
  );
}
