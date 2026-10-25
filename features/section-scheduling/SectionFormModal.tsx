'use client';

// Create a section, or edit the name and capacity of one, in a centered modal
// (a focused form that fits one screen). The program and year level of an
// existing section never change, so they are shown but locked.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, NumberInput, Select, Stack, Text, TextInput } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
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
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseSectionInput({
    programId: programId ?? '',
    yearLevel: typeof yearLevel === 'number' ? yearLevel : Number.NaN,
    name,
    capacity: typeof capacity === 'number' ? capacity : Number.NaN,
  });

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || loading) return;
    setLoading(true);
    setError(null);
    const result = section
      ? await updateSection(section.id, { name: parsed.value.name, capacity: parsed.value.capacity })
      : await createSection(parsed.value);
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
      title={section ? 'Edit section' : 'New section'}
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
            <TextInput
              label="Name"
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
              maxLength={MAX_NAME}
              required
            />
          </Group>
          <NumberInput
            label="Capacity"
            description="Seats for automatic placement. A student can still be moved in by hand."
            value={capacity}
            onChange={setCapacity}
            min={1}
            max={MAX_CAPACITY}
            allowDecimal={false}
            allowNegative={false}
            required
          />
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
              {section ? 'Save section' : 'Create section'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
