'use client';

// Import the subjects of one program from a CSV or Excel file, in a centered
// modal. The template is downloaded from here and filled in; the chosen file is
// read in the browser and checked row by row with the same rules as Add subject.
// The Import button stays disabled until every row is valid, and the hint says
// why. A code the program already has is skipped, not changed. The server
// checks everything again (importSubjects).
import { useMemo, useRef, useState } from 'react';
import { Anchor, FileInput, Stack, Text } from '@mantine/core';
import { color, spacing } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { importSubjects, type ContentActionResult } from './actions';
import {
  SUBJECT_TEMPLATE_CSV,
  SUBJECT_TEMPLATE_XLSX,
  parseSubjectSheet,
  type SubjectSheet,
} from './importSubjects';
import { readSubjectFile } from './readSubjectFile';

// Problems listed in the modal; the rest are counted, so a bad file does not fill the screen.
const SHOWN_PROBLEMS = 5;

function subjectCount(count: number): string {
  return `${count} ${count === 1 ? 'subject' : 'subjects'}`;
}

export function SubjectImportModal({
  program,
  existingCodes,
  onClose,
  onDone,
}: {
  program: ProgramOption;
  existingCodes: string[]; // the codes the program already has
  onClose: () => void;
  onDone: (result: ContentActionResult) => void;
}) {
  const [file, setFile] = useState<File | null>(null);
  const [sheet, setSheet] = useState<SubjectSheet | null>(null);
  const [reading, setReading] = useState(false);
  const { loading, error, run } = useFormAction(onDone);
  const latestRead = useRef(0); // a slow read of an earlier file must not replace a later choice

  const existing = useMemo(() => new Set(existingCodes.map((code) => code.trim().toLowerCase())), [existingCodes]);

  async function onFile(next: File | null) {
    const mine = ++latestRead.current;
    setFile(next);
    setSheet(null);
    if (!next) {
      setReading(false);
      return;
    }
    setReading(true);
    const read = await readSubjectFile(next);
    if (mine !== latestRead.current) return;
    setSheet(read.ok ? parseSubjectSheet(read.grid, program.id) : read);
    setReading(false);
  }

  const rows = sheet?.ok ? sheet.rows : [];
  const problems = sheet?.ok ? sheet.problems : [];
  const ready = rows.filter((item) => !existing.has(item.subject.code.toLowerCase()));
  const skipped = rows.length - ready.length;

  let hint: string | null = null;
  if (reading) hint = 'Reading the file.';
  else if (!file) hint = 'Choose the filled template.';
  else if (sheet?.ok && problems.length > 0) hint = 'Fix these rows in the file, then choose it again.';
  else if (sheet?.ok && ready.length === 0) hint = 'Every subject in the file is already in this program.';
  const canImport = !reading && sheet?.ok === true && problems.length === 0 && ready.length > 0;

  function onSubmit() {
    if (!canImport) return;
    void run(() =>
      importSubjects(
        program.id,
        ready.map((item) => item.subject),
      ),
    );
  }

  return (
    <FormModal
      title="Import subjects"
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error ?? (sheet && !sheet.ok ? sheet.reason : null)}
      hint={canImport ? null : hint}
      submitLabel={canImport ? `Import ${subjectCount(ready.length)}` : 'Import'}
      submitDisabled={!canImport}
    >
      <Text size="sm" c={color.textSecondary}>
        Subjects are added to {program.code}. Download the template, fill it in, then choose it here.
      </Text>
      <Text size="sm">
        Template:{' '}
        <Anchor href={SUBJECT_TEMPLATE_XLSX} download>
          Excel (.xlsx)
        </Anchor>
        {', '}
        <Anchor href={SUBJECT_TEMPLATE_CSV} download>
          CSV (.csv)
        </Anchor>
      </Text>
      <FileInput
        label="File"
        placeholder="Choose a .csv or .xlsx file"
        accept=".csv,.xlsx"
        value={file}
        onChange={(next) => void onFile(next)}
        clearable
        disabled={loading}
      />

      {sheet?.ok && (
        <Stack gap={spacing.xs}>
          <Text size="sm">
            {subjectCount(ready.length)} ready to import
            {skipped > 0 ? `, ${skipped} already in ${program.code} and skipped` : ''}.
          </Text>
          {problems.slice(0, SHOWN_PROBLEMS).map((problem) => (
            <Text key={problem.row} size="sm" c={color.error}>
              Row {problem.row}: {problem.reason}
            </Text>
          ))}
          {problems.length > SHOWN_PROBLEMS && (
            <Text size="sm" c={color.error}>
              {problems.length - SHOWN_PROBLEMS} more rows have problems.
            </Text>
          )}
        </Stack>
      )}
    </FormModal>
  );
}
