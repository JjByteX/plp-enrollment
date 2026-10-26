'use client';

// Sets the prerequisites of one subject in a small centered modal: a multi-select of the
// earlier subjects of the same program. All the chosen subjects are required. The database
// refuses a loop, another program and a later subject, and its message is shown as written.
import { useState } from 'react';
import { MultiSelect, Text } from '@mantine/core';
import { FormModal, useFormAction } from '@/components/FormModal';
import { color } from '@/styles/tokens';
import { savePrerequisites, type PrerequisiteActionResult } from './actions';
import { earlierSubjects, type SubjectPrerequisites } from './schema';

export function EditPrerequisitesModal({
  subject,
  subjects,
  onClose,
  onDone,
}: {
  subject: SubjectPrerequisites;
  subjects: SubjectPrerequisites[]; // every subject of the program, for the choices
  onClose: () => void;
  onDone: (result: PrerequisiteActionResult) => void;
}) {
  const saved = subject.prerequisites.map((item) => item.subjectId);
  const [selected, setSelected] = useState<string[]>(saved);
  const { loading, error, run } = useFormAction<PrerequisiteActionResult>(onDone);

  // The earlier subjects in curriculum order, plus anything already saved so it can be removed.
  const choices = new Map<string, string>();
  for (const item of earlierSubjects(subjects, subject)) choices.set(item.subjectId, `${item.code}, ${item.title}`);
  for (const item of subject.prerequisites) choices.set(item.subjectId, `${item.code}, ${item.title}`);
  const options = Array.from(choices, ([value, label]) => ({ value, label }));

  const changed = selected.length !== saved.length || selected.some((id) => !saved.includes(id));

  function onSubmit() {
    if (!changed) return;
    void run(() => savePrerequisites({ subjectId: subject.subjectId, requiredIds: selected }));
  }

  return (
    <FormModal
      title={`Prerequisites of ${subject.code}`}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={changed ? null : 'Choose or remove a prerequisite to save.'}
      submitLabel="Save"
      submitDisabled={!changed}
    >
      <Text size="sm" c={color.textSecondary}>
        {subject.code}, {subject.title}
      </Text>
      {options.length === 0 ? (
        <Text c={color.textSecondary}>
          No earlier subject in this program yet. A prerequisite must be in a lower year level, or in the same year level
          and an earlier semester.
        </Text>
      ) : (
        <MultiSelect
          label="Must be passed first"
          description="Every subject chosen here is required"
          placeholder={selected.length === 0 ? 'None' : undefined}
          data={options}
          value={selected}
          onChange={setSelected}
          searchable
          clearable
          nothingFoundMessage="No matching subject"
          disabled={loading}
        />
      )}
    </FormModal>
  );
}
