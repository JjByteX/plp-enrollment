'use client';

// Who is booked in one slot, with a "move to another slot" control for each
// applicant whose visit has not happened yet. The reason is optional and goes
// into the audit log.
import { useState } from 'react';
import { Button, Divider, Group, Modal, Select, Stack, Text, TextInput } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { assignSlot, type VisitActionResult } from './actions';
import type { SlotBooking, SlotRow } from './queries';
import { MAX_REASON, formatSlotDate, windowLabel } from './schema';

export function slotOptionLabel(slot: SlotRow): string {
  return `${formatSlotDate(slot.slotDate)}, ${windowLabel(slot.startTime, slot.endTime)}, ${slot.officeName} (${slot.freeSeats} free)`;
}

const STATUS_LABEL: Record<SlotBooking['status'], string> = {
  booked: 'Booked',
  attended: 'Attended',
  no_show: 'No show',
};

export function SlotDetailsModal({
  slot,
  moveTargets,
  onClose,
  onDone,
}: {
  slot: SlotRow;
  moveTargets: SlotRow[]; // open slots of the same program with a free seat, not this one
  onClose: () => void;
  onDone: (result: VisitActionResult) => void;
}) {
  const [picks, setPicks] = useState<Record<string, string | null>>({});
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const options = moveTargets.map((target) => ({ value: target.id, label: slotOptionLabel(target) }));

  async function move(booking: SlotBooking) {
    const target = picks[booking.applicantId];
    if (!target || busy) return;
    setBusy(booking.applicantId);
    setError(null);
    const result = await assignSlot(booking.applicantId, target, reasons[booking.applicantId]);
    setBusy(null);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onDone({ ok: true, message: `${booking.fullName} moved.` });
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title={`${slot.programCode}, ${formatSlotDate(slot.slotDate)}, ${windowLabel(slot.startTime, slot.endTime)}`}
      padding={padding.modal}
      radius="lg"
      size="lg"
    >
      <Stack gap={spacing.md}>
        {slot.bookings.length === 0 ? (
          <Text c={color.textSecondary}>Nobody is booked in this slot.</Text>
        ) : (
          slot.bookings.map((booking, index) => (
            <Stack key={booking.bookingId} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between">
                <Text>
                  {booking.fullName} ({booking.applicantRef})
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {STATUS_LABEL[booking.status]}
                </Text>
              </Group>
              {booking.status === 'booked' && (
                <Stack gap={spacing.sm}>
                  <Select
                    aria-label={`Move ${booking.fullName} to slot`}
                    placeholder={options.length === 0 ? 'No other open slot with a free seat' : 'Move to slot'}
                    data={options}
                    value={picks[booking.applicantId] ?? null}
                    onChange={(value) => setPicks((current) => ({ ...current, [booking.applicantId]: value }))}
                    disabled={options.length === 0 || busy !== null}
                  />
                  <TextInput
                    aria-label={`Reason for moving ${booking.fullName}`}
                    placeholder="Reason (optional)"
                    maxLength={MAX_REASON}
                    value={reasons[booking.applicantId] ?? ''}
                    onChange={(event) => {
                      const value = event.currentTarget.value;
                      setReasons((current) => ({ ...current, [booking.applicantId]: value }));
                    }}
                    disabled={busy !== null}
                  />
                  <Group justify="flex-end">
                    <Button
                      variant="default"
                      loading={busy === booking.applicantId}
                      disabled={!picks[booking.applicantId] || busy !== null}
                      onClick={() => move(booking)}
                    >
                      Move
                    </Button>
                  </Group>
                </Stack>
              )}
            </Stack>
          ))
        )}
        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}
      </Stack>
    </Modal>
  );
}
