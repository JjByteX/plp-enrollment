'use client';

// Add or edit one subject, in a centered modal (a focused form that fits one
// screen). The save button stays disabled until the input is valid and the
// reason is shown. Editing keeps the program and year level; deleting asks
// once more first.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, NumberInput, Select, Stack, Switch, Text, TextInput } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { yearLabel } from '@/features/cor/schema';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { addSubject, deleteSubject, editSubject, type ContentActionResult } from './actions';
import type { SubjectRow } from './queries';
import { MAX_CODE, MAX_TITLE, MAX_UNITS, MAX_YEAR, parseSubjectEdit, parseSubjectInput } from './schema';

const YEAR_OPTIONS = Array.from({ length: MAX_YEAR }, (_, index) => ({
  value: String(index + 1),
  label: yearLabel(index + 1),
}));

function asNumber(value: number | string): number {
  return typeof value === 'number' ? value : Number.NaN;
}

export function SubjectModal({
  program,
  subject,
  onClose,
  onDone,
}: {
  program: ProgramOption;
  subject: SubjectRow | null; // null adds a subject
  onClose: () => void;
  onDone: (result: ContentActionResult) => void;
}) {
  const [code, setCode] = useState(subject?.code ?? '');
  const [title, setTitle] = useState(subject?.title ?? '');
  const [units, setUnits] = useState<number | string>(subject?.units ?? '');
  const [year, setYear] = useState<string | null>(null);
  const [hasLaboratory, setHasLaboratory] = useState(subject?.hasLaboratory ?? false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const fields = { code, title, units: asNumber(units), hasLaboratory };
  const parsed = subject
    ? parseSubjectEdit(fields)
    : parseSubjectInput({ ...fields, programId: program.id, yearLevel: year === null ? null : Number(year) });

  async function run(action: () => Promise<ContentActionResult>) {
    if (loading) return;
    setLoading(true);
    setError(null);
    const result = await action();
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      setConfirmDelete(false);
      return;
    }
    onDone(result);
  }

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok) return;
    void run(() => (subject ? editSubject(subject.id, parsed.value) : addSubject(parsed.value)));
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title={subject ? 'Edit subject' : 'Add subject'}
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <Text size="sm" c={color.textSecondary}>
            {program.code}
            {subject ? `, ${subject.yearLevel === null ? 'no year level' : yearLabel(subject.yearLevel)}` : ''}
          </Text>
          <TextInput
            label="Code"
            value={code}
            onChange={(event) => setCode(event.currentTarget.value)}
            maxLength={MAX_CODE}
            required
          />
          <TextInput
            label="Title"
            value={title}
            onChange={(event) => setTitle(event.currentTarget.value)}
            maxLength={MAX_TITLE}
            required
          />
          <NumberInput
            label="Units"
            decimalScale={1}
            min={0}
            max={MAX_UNITS}
            allowNegative={false}
            value={units}
            onChange={setUnits}
            required
          />
          {!subject && <Select label="Year level" data={YEAR_OPTIONS} value={year} onChange={setYear} required />}
          <Switch
            label="Has a laboratory"
            checked={hasLaboratory}
            onChange={(event) => setHasLaboratory(event.currentTarget.checked)}
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
              {subject ? 'Save' : 'Add subject'}
            </Button>
          </Group>
          {subject && (
            <Group justify="flex-start">
              {confirmDelete ? (
                <Group gap={spacing.sm}>
                  <Text size="sm">Delete this subject?</Text>
                  <Button
                    variant="default"
                    size="xs"
                    color={color.error}
                    disabled={loading}
                    onClick={() => void run(() => deleteSubject(subject.id))}
                  >
                    Delete
                  </Button>
                  <Button variant="subtle" size="xs" disabled={loading} onClick={() => setConfirmDelete(false)}>
                    Keep
                  </Button>
                </Group>
              ) : (
                <Button variant="subtle" size="xs" color={color.error} disabled={loading} onClick={() => setConfirmDelete(true)}>
                  Delete subject
                </Button>
              )}
            </Group>
          )}
        </Stack>
      </form>
    </Modal>
  );
}
