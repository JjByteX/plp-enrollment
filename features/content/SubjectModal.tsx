'use client';

// Add or edit one subject, in a centered modal (a focused form that fits one
// screen). The save button stays disabled until the input is valid and the
// reason is shown. Editing keeps the program and year level; deleting asks
// once more first.
import { useState } from 'react';
import { Button, Group, NumberInput, Select, Switch, Text, TextInput } from '@mantine/core';
import { color, spacing } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { asNumber, reasonOf } from '@/lib/validate';
import { SEMESTER_LABEL, yearLabel, type Semester } from '@/features/cor/schema';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { addSubject, deleteSubject, editSubject, type ContentActionResult } from './actions';
import type { SubjectRow } from './queries';
import { MAX_CODE, MAX_TITLE, MAX_UNITS, MAX_YEAR, parseSubjectEdit, parseSubjectInput } from './schema';

const YEAR_OPTIONS = Array.from({ length: MAX_YEAR }, (_, index) => ({
  value: String(index + 1),
  label: yearLabel(index + 1),
}));

const SEMESTER_OPTIONS = (Object.keys(SEMESTER_LABEL) as Semester[]).map((value) => ({
  value,
  label: SEMESTER_LABEL[value],
}));

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
  const [semester, setSemester] = useState<string | null>(null);
  const [hasLaboratory, setHasLaboratory] = useState(subject?.hasLaboratory ?? false);
  const [offeredInSummer, setOfferedInSummer] = useState(subject?.offeredInSummer ?? false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const { loading, error, run } = useFormAction(onDone);

  const summerOnly = (subject ? subject.semester : semester) === 'summer';
  const fields = { code, title, units: asNumber(units), hasLaboratory, offeredInSummer: summerOnly ? false : offeredInSummer };
  const parsed = subject
    ? parseSubjectEdit(fields)
    : parseSubjectInput({ ...fields, programId: program.id, yearLevel: year === null ? null : Number(year), semester });

  async function runAction(action: () => Promise<ContentActionResult>) {
    if (!(await run(action))) setConfirmDelete(false);
  }

  function onSubmit() {
    if (!parsed.ok) return;
    void runAction(() => (subject ? editSubject(subject.id, parsed.value) : addSubject(parsed.value)));
  }

  return (
    <FormModal
      title={subject ? 'Edit subject' : 'Add subject'}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel={subject ? 'Save' : 'Add subject'}
      submitDisabled={!parsed.ok}
      footer={
        subject && (
          <Group justify="flex-start">
            {confirmDelete ? (
              <Group gap={spacing.sm}>
                <Text size="sm">Delete this subject?</Text>
                <Button
                  variant="default"
                  size="xs"
                  color={color.error}
                  disabled={loading}
                  onClick={() => void runAction(() => deleteSubject(subject.id))}
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
        )
      }
    >
      <Text size="sm" c={color.textSecondary}>
        {program.code}
        {subject
          ? `, ${subject.yearLevel === null ? 'no year level' : yearLabel(subject.yearLevel)}, ${SEMESTER_LABEL[subject.semester as Semester] ?? subject.semester}`
          : ''}
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
      {!subject && <Select label="Semester" data={SEMESTER_OPTIONS} value={semester} onChange={setSemester} required />}
      <Switch
        label="Has a laboratory"
        checked={hasLaboratory}
        onChange={(event) => setHasLaboratory(event.currentTarget.checked)}
      />
      {!summerOnly && (
        <Switch
          label="Also offered in summer"
          checked={offeredInSummer}
          onChange={(event) => setOfferedInSummer(event.currentTarget.checked)}
        />
      )}
    </FormModal>
  );
}
