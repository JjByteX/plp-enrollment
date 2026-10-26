'use client';

// Create or edit one visit slot, in a centered modal (a focused form that
// fits one screen). A slot with applicants booked keeps its program, date,
// time and office; the database refuses those changes, so the fields are
// locked here and the reason is stated once.
import { useState } from 'react';
import { Group, NumberInput, Select, Text, TextInput, Textarea } from '@mantine/core';
import { color, spacing } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { asNumber, reasonOf } from '@/lib/validate';
import { createSlot, updateSlot, type VisitActionResult } from './actions';
import type { ProgramOption, SlotRow } from './queries';
import { MAX_CAPACITY, manilaToday, parseSlotInput } from './schema';

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
  const [whatToBring, setWhatToBring] = useState(slot?.whatToBring ?? '');
  const { loading, error, run } = useFormAction(onDone);

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
      capacity: asNumber(capacity),
      officeName,
      whatToBring,
    },
    dateToday
  );

  function onSubmit() {
    if (!parsed.ok) return;
    void run(() => (slot ? updateSlot(slot.id, parsed.value) : createSlot(parsed.value)));
  }

  return (
    <FormModal
      title={slot ? 'Edit slot' : 'New slot'}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel={slot ? 'Save slot' : 'Create slot'}
      submitDisabled={!parsed.ok}
    >
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
        label="Extra notes"
        description="Shown after the documents listed for the applicant's admission type"
        value={whatToBring}
        onChange={(event) => setWhatToBring(event.currentTarget.value)}
        autosize
        minRows={3}
        maxRows={8}
        maxLength={2000}
      />
      {locked && (
        <Text size="sm" c={color.textSecondary}>
          Date, time and office are locked while applicants are booked. Close the slot and move them instead.
        </Text>
      )}
    </FormModal>
  );
}
