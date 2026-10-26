'use client';

// The Registrar's visits page body: filters, the list of applicants waiting
// for a visit, and the slot table. Slot form and slot details open as
// centered modals. All changes go through ./actions.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Modal, Select, Stack, Table, Text, TextInput, Title } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, padding, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import {
  assignAllUnassigned,
  assignSlot,
  setSlotStatus,
  type VisitActionResult,
} from './actions';
import type { ProgramOption, SlotRow, UnassignedApplicant } from './queries';
import { formatSlotDate, windowLabel } from './schema';
import { SlotDetailsModal, slotOptionLabel } from './SlotDetailsModal';
import { SlotFormModal } from './SlotFormModal';

const STATUS_LABEL: Record<SlotRow['status'], string> = {
  open: 'Open',
  closed: 'Closed',
  cancelled: 'Cancelled',
};

export function VisitsAdmin({
  programs,
  programId,
  date,
  today,
  slots,
  unassigned,
}: {
  programs: ProgramOption[];
  programId: string | null;
  date: string | null;
  today: string;
  slots: SlotRow[]; // every slot of the chosen program (or of all programs), not filtered by date
  unassigned: UnassignedApplicant[];
}) {
  const router = useRouter();
  const [message, setMessage] = useState<VisitActionResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [form, setForm] = useState<{ slot: SlotRow | null } | null>(null);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState<SlotRow | null>(null);
  const [picks, setPicks] = useState<Record<string, string | null>>({});

  const rows = date ? slots.filter((slot) => slot.slotDate === date) : slots;
  const detail = detailId ? (slots.find((slot) => slot.id === detailId) ?? null) : null;

  // A slot an applicant can still be put into: open, a free seat, not already over.
  const canTake = (slot: SlotRow) => slot.status === 'open' && slot.freeSeats > 0 && slot.slotDate >= today;
  const pickable = programId ? slots.filter((slot) => slot.programId === programId && canTake(slot)) : [];
  const pickOptions = pickable.map((slot) => ({ value: slot.id, label: slotOptionLabel(slot) }));

  function setFilter(next: { program?: string | null; date?: string | null }) {
    const params = new URLSearchParams();
    const nextProgram = next.program === undefined ? programId : next.program;
    const nextDate = next.date === undefined ? date : next.date;
    if (nextProgram) params.set('program', nextProgram);
    if (nextDate) params.set('date', nextDate);
    const query = params.toString();
    router.push(query ? `/registrar/visits?${query}` : '/registrar/visits');
  }

  async function run(key: string, action: () => Promise<VisitActionResult>) {
    setBusy(key);
    setMessage(null);
    const result = await action();
    setMessage(result);
    setBusy(null);
    return result;
  }

  function finish(result: VisitActionResult) {
    setForm(null);
    setDetailId(null);
    setMessage(result);
  }

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between">
        <PageHeading title="Visits" parent={{ label: 'Registrar', href: '/registrar' }} />
        <Button onClick={() => setForm({ slot: null })} disabled={programs.length === 0}>
          New slot
        </Button>
      </Group>

      <Group gap={spacing.md} align="flex-end">
        <Select
          label="Program"
          placeholder="All programs"
          data={programs.map((program) => ({ value: program.id, label: `${program.code} - ${program.name}` }))}
          value={programId}
          onChange={(value) => setFilter({ program: value })}
          searchable
          clearable
        />
        <TextInput
          label="Date"
          type="date"
          value={date ?? ''}
          onChange={(event) => setFilter({ date: event.currentTarget.value || null })}
        />
      </Group>

      <FormMessage message={message} />

      <Divider />

      <Stack gap={spacing.md}>
        <Group justify="space-between">
          <Title order={4}>Waiting for a visit</Title>
          {programId && unassigned.length > 0 && (
            <Button
              variant="default"
              loading={busy === 'all'}
              disabled={busy !== null || pickable.length === 0}
              onClick={() => run('all', () => assignAllUnassigned(programId))}
            >
              Assign all unassigned
            </Button>
          )}
        </Group>

        {!programId ? (
          <Text c={color.textSecondary}>Choose a program to see who is waiting.</Text>
        ) : unassigned.length === 0 ? (
          <Text c={color.textSecondary}>Nobody is waiting for a visit.</Text>
        ) : (
          <>
            {pickable.length === 0 && (
              <Text size="sm" c={color.textSecondary}>
                No open slot with a free seat. Create a slot to assign these applicants.
              </Text>
            )}
            <Table.ScrollContainer minWidth={720}>
              <Table>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Applicant</Table.Th>
                    <Table.Th>Reference</Table.Th>
                    <Table.Th>Admitted</Table.Th>
                    <Table.Th>Slot</Table.Th>
                    <Table.Th />
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {unassigned.map((applicant) => (
                    <Table.Tr key={applicant.applicantId}>
                      <Table.Td>{applicant.fullName}</Table.Td>
                      <Table.Td>{applicant.applicantRef}</Table.Td>
                      <Table.Td>{formatSlotDate(applicant.admissionDate)}</Table.Td>
                      <Table.Td>
                        <Select
                          aria-label={`Slot for ${applicant.fullName}`}
                          placeholder="Choose a slot"
                          data={pickOptions}
                          value={picks[applicant.applicantId] ?? null}
                          onChange={(value) => setPicks((current) => ({ ...current, [applicant.applicantId]: value }))}
                          disabled={pickOptions.length === 0 || busy !== null}
                        />
                      </Table.Td>
                      <Table.Td>
                        <Button
                          variant="default"
                          loading={busy === applicant.applicantId}
                          disabled={!picks[applicant.applicantId] || busy !== null}
                          onClick={async () => {
                            const slotId = picks[applicant.applicantId];
                            if (!slotId) return;
                            const result = await run(applicant.applicantId, () => assignSlot(applicant.applicantId, slotId));
                            if ('ok' in result) setPicks((current) => ({ ...current, [applicant.applicantId]: null }));
                          }}
                        >
                          Assign
                        </Button>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </>
        )}
      </Stack>

      <Divider />

      <Stack gap={spacing.md}>
        <Title order={4}>Slots</Title>
        {rows.length === 0 ? (
          <Text c={color.textSecondary}>{date ? 'No slots on this date.' : 'No slots yet.'}</Text>
        ) : (
          <Table.ScrollContainer minWidth={900}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Time</Table.Th>
                  <Table.Th>Program</Table.Th>
                  <Table.Th>Office</Table.Th>
                  <Table.Th>Booked</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((slot) => (
                  <Table.Tr key={slot.id}>
                    <Table.Td>{formatSlotDate(slot.slotDate)}</Table.Td>
                    <Table.Td>{windowLabel(slot.startTime, slot.endTime)}</Table.Td>
                    <Table.Td>{slot.programCode}</Table.Td>
                    <Table.Td>{slot.officeName}</Table.Td>
                    <Table.Td>
                      {slot.bookings.length} of {slot.capacity}
                    </Table.Td>
                    <Table.Td>{STATUS_LABEL[slot.status]}</Table.Td>
                    <Table.Td>
                      <Group gap={spacing.sm} wrap="nowrap" justify="flex-end">
                        <Button variant="default" size="xs" onClick={() => setDetailId(slot.id)}>
                          View
                        </Button>
                        {slot.status !== 'cancelled' && (
                          <Button variant="default" size="xs" onClick={() => setForm({ slot })}>
                            Edit
                          </Button>
                        )}
                        {slot.status === 'open' && (
                          <Button
                            variant="default"
                            size="xs"
                            loading={busy === `close-${slot.id}`}
                            disabled={busy !== null}
                            onClick={() => run(`close-${slot.id}`, () => setSlotStatus(slot.id, 'closed'))}
                          >
                            Close
                          </Button>
                        )}
                        {slot.status === 'closed' && (
                          <Button
                            variant="default"
                            size="xs"
                            loading={busy === `open-${slot.id}`}
                            disabled={busy !== null}
                            onClick={() => run(`open-${slot.id}`, () => setSlotStatus(slot.id, 'open'))}
                          >
                            Reopen
                          </Button>
                        )}
                        {slot.status !== 'cancelled' && slot.bookings.length === 0 && (
                          <Button variant="default" size="xs" disabled={busy !== null} onClick={() => setCancelling(slot)}>
                            Cancel
                          </Button>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Stack>

      {form && (
        <SlotFormModal
          slot={form.slot}
          programs={programs}
          defaultProgramId={programId}
          onClose={() => setForm(null)}
          onDone={finish}
        />
      )}

      {detail && (
        <SlotDetailsModal
          slot={detail}
          moveTargets={slots.filter((slot) => slot.programId === detail.programId && slot.id !== detail.id && canTake(slot))}
          onClose={() => setDetailId(null)}
          onDone={finish}
        />
      )}

      {cancelling && (
        <Modal
          opened
          onClose={() => setCancelling(null)}
          title="Cancel slot"
          padding={padding.modal}
          radius="lg"
          size="sm"
        >
          <Stack gap={spacing.md}>
            <Text>
              Cancel {cancelling.programCode} on {formatSlotDate(cancelling.slotDate)},{' '}
              {windowLabel(cancelling.startTime, cancelling.endTime)}? A cancelled slot cannot be reopened.
            </Text>
            <Group justify="space-between">
              <Button variant="default" onClick={() => setCancelling(null)}>
                Keep slot
              </Button>
              <Button
                color="red"
                loading={busy === `cancel-${cancelling.id}`}
                onClick={async () => {
                  const target = cancelling;
                  await run(`cancel-${target.id}`, () => setSlotStatus(target.id, 'cancelled'));
                  setCancelling(null);
                }}
              >
                Cancel slot
              </Button>
            </Group>
          </Stack>
        </Modal>
      )}
    </Stack>
  );
}
