'use client';

// The mass reschedule tab: pick the affected date, optionally one program or
// office, give the reason, and confirm. The date is a URL filter (like the
// visits page) so the server can count the booked visits on it. The button
// stays disabled until the input is valid, and the reason is shown.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Group, Modal, Select, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { massReschedule, type MassActionResult } from './actions';
import type { BookedVisit } from './queries';
import { MAX_REASON, formatSlotDate, parseMassInput, visitCount } from './schema';

export function MassReschedulePanel({
  date,
  today,
  booked,
  onResult,
}: {
  date: string | null;
  today: string;
  booked: BookedVisit[]; // visits still booked on the chosen date
  onResult: (result: MassActionResult | null) => void;
}) {
  const router = useRouter();
  const [programId, setProgramId] = useState<string | null>(null);
  const [officeName, setOfficeName] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  // A choice made for another date may not exist on this one.
  const programs = Array.from(new Map(booked.map((visit) => [visit.programId, visit.programCode])).entries());
  const programValue = programs.some(([id]) => id === programId) ? programId : null;
  const inProgram = programValue ? booked.filter((visit) => visit.programId === programValue) : booked;
  const offices = Array.from(new Set(inProgram.map((visit) => visit.officeName))).sort();
  const officeValue = officeName !== null && offices.includes(officeName) ? officeName : null;
  const affected = officeValue ? inProgram.filter((visit) => visit.officeName === officeValue) : inProgram;

  const parsed = parseMassInput({ date: date ?? '', programId: programValue, officeName: officeValue, reason }, today);
  const nothingBooked = date !== null && affected.length === 0;

  function setDate(next: string) {
    onResult(null);
    router.push(next ? `/registrar/reschedules?tab=mass&date=${next}` : '/registrar/reschedules?tab=mass');
  }

  async function confirm() {
    if (!parsed.ok || busy) return;
    setBusy(true);
    const result = await massReschedule(parsed.value);
    setBusy(false);
    setConfirming(false);
    onResult(result);
    if ('ok' in result) setReason('');
  }

  return (
    <Stack gap={spacing.md}>
      <TextInput
        label="Affected date"
        type="date"
        min={today}
        value={date ?? ''}
        onChange={(event) => setDate(event.currentTarget.value)}
        disabled={busy}
      />
      <Group gap={spacing.md} align="flex-end" grow>
        <Select
          label="Program"
          placeholder="All programs"
          data={programs.map(([id, code]) => ({ value: id, label: code }))}
          value={programValue}
          onChange={setProgramId}
          disabled={programs.length === 0 || busy}
          clearable
        />
        <Select
          label="Office"
          placeholder="All offices"
          data={offices}
          value={officeValue}
          onChange={setOfficeName}
          disabled={offices.length === 0 || busy}
          clearable
        />
      </Group>
      <Textarea
        label="Reason"
        description="Kept in the audit log. Each person is told their new date."
        value={reason}
        onChange={(event) => setReason(event.currentTarget.value)}
        maxLength={MAX_REASON}
        minRows={2}
        autosize
        disabled={busy}
      />

      {date !== null && (
        <Text size="sm" c={color.textSecondary}>
          {nothingBooked ? 'No booked visit falls on this date.' : `${visitCount(affected.length)} will be moved.`}
        </Text>
      )}
      {!parsed.ok && (
        <Text size="sm" c={color.textSecondary}>
          {parsed.reason}
        </Text>
      )}

      <Group justify="flex-end">
        <Button disabled={!parsed.ok || nothingBooked || busy} onClick={() => setConfirming(true)}>
          Move visits
        </Button>
      </Group>

      {confirming && parsed.ok && (
        <Modal
          opened
          onClose={() => setConfirming(false)}
          title="Move visits"
          padding={padding.modal}
          radius="lg"
          size="sm"
          closeOnClickOutside={!busy}
        >
          <Stack gap={spacing.md}>
            <Text>
              Move {visitCount(affected.length)} on {formatSlotDate(parsed.value.date)} to the next open slot? Each
              person is told on their next step card and by email. This cannot be undone.
            </Text>
            <Group justify="space-between">
              <Button variant="default" onClick={() => setConfirming(false)} disabled={busy}>
                Cancel
              </Button>
              <Button loading={busy} onClick={() => void confirm()}>
                Move
              </Button>
            </Group>
          </Stack>
        </Modal>
      )}
    </Stack>
  );
}
