'use client';

// One grade sheet as a centered modal (step 19). The Professor types a grade per
// student and submits; the Dean approves (which locks the grades) or returns the
// sheet with a reason; after approval the Professor proposes a change per student.
// The Registrar only reads. Admin can do every step. The database checks each step again.
import { useState } from 'react';
import { Button, Divider, Group, Modal, Stack, Table, Text, TextInput } from '@mantine/core';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import type { Role } from '@/lib/auth/roles';
import { approveGrades, proposeChange, returnGrades, saveGrades, submitGrades, type GradingActionResult } from './actions';
import { ReasonDialog } from './ReasonModal';
import { OUTCOME_LABEL, STATUS_LABEL, type Sheet, type SheetStudent } from './schema';

type Dialog = { kind: 'return' } | { kind: 'change'; student: SheetStudent } | null;

export function SheetModal({
  sheet,
  viewerRole,
  ready,
  onClose,
  onDone,
}: {
  sheet: Sheet;
  viewerRole: Role;
  ready: boolean; // a grading scale is set
  onClose: () => void;
  onDone: (result: GradingActionResult) => void;
}) {
  const [typed, setTyped] = useState<Record<string, string>>(
    Object.fromEntries(sheet.students.map((student) => [student.studentId, student.gradeText ?? ''])),
  );
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [dialog, setDialog] = useState<Dialog>(null);

  const isProfessor = viewerRole === 'professor' || viewerRole === 'admin';
  const isDean = viewerRole === 'dean' || viewerRole === 'admin';
  const open = sheet.status === 'not_submitted' || sheet.status === 'draft';
  const canEnter = isProfessor && open && ready;
  const canDecide = isDean && sheet.status === 'submitted';
  const canPropose = isProfessor && sheet.status === 'approved';

  const entries = sheet.students.map((student) => ({ studentId: student.studentId, grade: typed[student.studentId] ?? '' }));

  async function run(work: () => Promise<GradingActionResult>) {
    if (loading) return;
    setLoading(true);
    setError(null);
    const result = await work();
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onDone(result);
  }

  async function saveThenSubmit() {
    await run(async () => {
      const saved = await saveGrades(sheet.sectionId, sheet.subjectId, entries);
      if ('error' in saved) return saved;
      return submitGrades(sheet.sectionId, sheet.subjectId);
    });
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title={`${sheet.label}, ${sheet.code}`}
      size="xl"
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <Stack gap={spacing.md}>
        <Stack gap={spacing.xs}>
          <Text fw={fontWeight.semibold}>{sheet.title}</Text>
          <Text size="sm" c={color.textSecondary}>
            {sheet.schoolYear}, {sheet.semester}. {STATUS_LABEL[sheet.status]}.
          </Text>
          {sheet.returnedReason && open && (
            <Text size="sm" c={color.error}>
              Returned by the Dean: {sheet.returnedReason}
            </Text>
          )}
          {isProfessor && open && !ready && (
            <Text size="sm" c={color.textSecondary}>
              The grading scale is not set. Ask Admin to set it in Content, Grading.
            </Text>
          )}
        </Stack>
        <Divider />

        {sheet.students.length === 0 ? (
          <Text c={color.textSecondary}>No student is placed in this section.</Text>
        ) : (
          <Table.ScrollContainer minWidth={480}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Student number</Table.Th>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Grade</Table.Th>
                  <Table.Th>Outcome</Table.Th>
                  {canPropose && <Table.Th />}
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {sheet.students.map((student) => (
                  <Table.Tr key={student.studentId}>
                    <Table.Td>{student.studentNumber}</Table.Td>
                    <Table.Td>{student.fullName}</Table.Td>
                    <Table.Td>
                      {canEnter ? (
                        <TextInput
                          aria-label={`Grade of ${student.fullName}`}
                          value={typed[student.studentId] ?? ''}
                          onChange={(event) => setTyped((current) => ({ ...current, [student.studentId]: event.currentTarget.value }))}
                          maxLength={30}
                          w={110}
                        />
                      ) : (
                        (student.gradeText ?? '')
                      )}
                    </Table.Td>
                    <Table.Td>
                      {student.outcome ? OUTCOME_LABEL[student.outcome] : ''}
                      {student.lapsed ? ' (lapsed)' : ''}
                      {student.changePending ? ' (change pending)' : ''}
                    </Table.Td>
                    {canPropose && (
                      <Table.Td>
                        {student.gradeId && !student.changePending && (
                          <Button variant="default" size="xs" onClick={() => setDialog({ kind: 'change', student })}>
                            Propose change
                          </Button>
                        )}
                      </Table.Td>
                    )}
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}

        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}

        <Group justify="space-between">
          <Button variant="default" onClick={onClose} disabled={loading}>
            Close
          </Button>
          <Group>
            {canEnter && (
              <>
                <Button variant="default" loading={loading} onClick={() => run(() => saveGrades(sheet.sectionId, sheet.subjectId, entries))}>
                  Save
                </Button>
                <Button loading={loading} onClick={saveThenSubmit}>
                  Submit to Dean
                </Button>
              </>
            )}
            {canDecide && (
              <>
                <Button variant="default" disabled={loading} onClick={() => setDialog({ kind: 'return' })}>
                  Return
                </Button>
                <Button loading={loading} onClick={() => run(() => approveGrades(sheet.sectionId, sheet.subjectId))}>
                  Approve
                </Button>
              </>
            )}
          </Group>
        </Group>
      </Stack>

      {dialog?.kind === 'return' && (
        <ReasonDialog
          title="Return grades"
          action="Return"
          hint="The Professor can edit the grades again and submit them once more."
          run={(reason) => returnGrades(sheet.sectionId, sheet.subjectId, reason)}
          onClose={() => setDialog(null)}
          onDone={(result) => {
            setDialog(null);
            onDone(result);
          }}
        />
      )}
      {dialog?.kind === 'change' && (
        <ReasonDialog
          title={`Propose a change for ${dialog.student.fullName}`}
          action="Propose"
          withGrade
          hint="The Dean signs it, then the Registrar approves it. Until then the grade stays as it is."
          run={(reason, grade) => proposeChange(dialog.student.gradeId as string, grade, reason)}
          onClose={() => setDialog(null)}
          onDone={(result) => {
            setDialog(null);
            onDone(result);
          }}
        />
      )}
    </Modal>
  );
}
