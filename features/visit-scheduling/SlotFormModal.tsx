'use client';

// Create or edit one visit slot, in a centered modal (a focused form that
// fits one screen). A slot with applicants booked keeps its program, date,
// time and office; the database refuses those changes, so the fields are
// locked here and the reason is stated once.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, NumberInput, Select, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { createSlot, updateSlot, type VisitActionResult } from './actions';
import type { ProgramOption, SlotRow } from './queries';
import { DEFAULT_WHAT_TO_BRING, MAX_CAPACITY, manilaToday, parseSlotInput } from './schema';

export function SlotFormModal({
  slot,
  programs,
  defaultProgramId,
  onClose,
  onDone,
}: {
  slot: SlotRow | null; // null = new slot
  programs: ProgramOption[];
  defaultProgramId: string | null;
  onClose: () => void;
  onDone: (result: VisitActionResult) => void;
}) {
  const [programId, setProgramId] = useState<string | null>(slot?.programId ?? defaultProgramId);
  const [slotDate, setSlotDate] = useState(slot?.slotDate ?? '');
  const [startTime, setStartTime] = useState(slot?.startTime ?? '');
  const [endTime, setEndTime] = useState(slot?.endTime ?? '');
  const [capacity, setCapacity] = useState<number | string>(slot?.capacity ?? 1);
  const [officeName, setOfficeName] = useState(slot?.officeName ?? '');
  const [whatToBring, setWhatToBring] = useState(slot?.whatToBring ?? DEFAULT_WHAT_TO_BRING);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const locked = slot !== null && slot.bookings.length > 0;
  const today = manilaToday();
  // An existing slot may keep its own (past) date; a new or changed date may not be in the past.
  const dateToday = slot && slot.slotDate === slotDate ? slotDate : today;

  const parsed = parseSlotInput(
    {
      programId: programId ?? '',
      slotDate,
      startTime,
      endTime,
      capacity: typeof capacity === 'number' ? capacity : Number.NaN,
      officeName,
      whatToBring,
    },
    dateToday
  );

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || loading) return;
    setLoading(true);
    setError(null);
    const result = slot ? await updateSlot(slot.id, parsed.value) : await createSlot(parsed.value);
    setLoading(false);
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
      title={slot ? 'Edit slot' : 'New slot'}
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <Select
            label="Program"
            data={programs.map((program) => ({ value: program.id, label: `${program.code} - ${program.name}` }))}
            value={programId}
            onChange={setProgramId}
            searchable
            disabled={locked}
            required
          />
          <TextInput
            label="Date"
            type="date"
            value={slotDate}
            min={slot ? undefined : today}
            onChange={(event) => setSlotDate(event.currentTarget.value)}
            disabled={locked}
            required
          />
          <Group grow gap={spacing.md} align="flex-start">
            <TextInput
              label="Start time"
              type="time"
              value={startTime}
              onChange={(event) => setStartTime(event.currentTarget.value)}
              disabled={locked}
              required
            />
            <TextInput
              label="End time"
              type="time"
              value={endTime}
              onChange={(event) => setEndTime(event.currentTarget.value)}
              disabled={locked}
              required
            />
          </Group>
          <NumberInput
            label="Capacity"
            value={capacity}
            onChange={setCapacity}
            min={slot ? Math.max(slot.bookings.length, 1) : 1}
            max={MAX_CAPACITY}
            allowDecimal={false}
            allowNegative={false}
            required
          />
          <TextInput
            label="Office"
            value={officeName}
            onChange={(event) => setOfficeName(event.currentTarget.value)}
            maxLength={100}
            disabled={locked}
            required
          />
          <Textarea
            label="What to bring"
            value={whatToBring}
            onChange={(event) => setWhatToBring(event.currentTarget.value)}
            autosize
            minRows={6}
            maxRows={12}
            maxLength={2000}
            required
          />
          {locked && (
            <Text size="sm" c={color.textSecondary}>
              Date, time and office are locked while applicants are booked. Close the slot and move them instead.
            </Text>
          )}
          {error && (
            <Text size="sm" c={color.error} role="alert">
              {error}
            </Text>
          )}
          {!parsed.ok && (
            <Text size="sm" c={color.textSecondary}>
              {parsed.reason}
            </Text>
          )}
          <Group justify="space-between">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading} disabled={!parsed.ok}>
              {slot ? 'Save slot' : 'Create slot'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
