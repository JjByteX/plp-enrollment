'use client';

// Create a section, or edit the name and capacity of one, in a centered modal
// (a focused form that fits one screen). The program and year level of an
// existing section never change, so they are shown but locked.
import { useState } from 'react';
import { Group, NumberInput, Select, TextInput } from '@mantine/core';
import { spacing } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { asNumber, reasonOf } from '@/lib/validate';
import { createSection, updateSection, type ScheduleActionResult } from './actions';
import type { ProgramOption, SectionRow } from './queries';
import { MAX_CAPACITY, MAX_NAME, MAX_YEAR, parseSectionInput } from './schema';

export function SectionFormModal({
  section,
  programs,
  defaultProgramId,
  onClose,
  onDone,
}: {
  section: SectionRow | null; // null = new section
  programs: ProgramOption[];
  defaultProgramId: string | null;
  onClose: () => void;
  onDone: (result: ScheduleActionResult) => void;
}) {
  const [programId, setProgramId] = useState<string | null>(section?.programId ?? defaultProgramId);
  const [yearLevel, setYearLevel] = useState<number | string>(section?.yearLevel ?? 1);
  const [name, setName] = useState(section?.name ?? '');
  const [capacity, setCapacity] = useState<number | string>(section?.capacity ?? '');
  const { loading, error, run } = useFormAction(onDone);

  const parsed = parseSectionInput({
    programId: programId ?? '',
    yearLevel: asNumber(yearLevel),
    capacity: asNumber(capacity),
  });

  const blankName = section !== null && name.trim() === '';

  function onSubmit() {
    if (!parsed.ok || blankName) return;
    void run(() =>
      section ? updateSection(section.id, { name: name.trim(), capacity: parsed.value.capacity }) : createSection(parsed.value)
    );
  }

  return (
    <FormModal
      title={section ? 'Edit section' : 'New section'}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel={section ? 'Save section' : 'Create section'}
      submitDisabled={!parsed.ok || blankName}
    >
      <Select
        label="Program"
        data={programs.map((program) => ({ value: program.id, label: `${program.code} - ${program.name}` }))}
        value={programId}
        onChange={setProgramId}
        searchable
        disabled={section !== null}
        required
      />
      <Group grow gap={spacing.md} align="flex-start">
        <NumberInput
          label="Year level"
          value={yearLevel}
          onChange={setYearLevel}
          min={1}
          max={MAX_YEAR}
          allowDecimal={false}
          allowNegative={false}
          disabled={section !== null}
          required
        />
        {section && (
          <TextInput
            label="Name"
            value={name}
            onChange={(event) => setName(event.currentTarget.value)}
            maxLength={MAX_NAME}
            required
          />
        )}
      </Group>
      <NumberInput
        label="Capacity"
        description={
          section
            ? 'Seats for automatic placement. A student can still be moved in by hand.'
            : 'Seats for automatic placement. The section is named with the next letter. A student can still be moved in by hand.'
        }
        value={capacity}
        onChange={setCapacity}
        min={1}
        max={MAX_CAPACITY}
        allowDecimal={false}
        allowNegative={false}
        required
      />
    </FormModal>
  );
}
