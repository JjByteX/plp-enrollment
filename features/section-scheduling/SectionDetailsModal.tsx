'use client';

// One section in a centered modal: the loading rows (subject, professor, room,
// day, time), the students in it, and the buttons for the chain: Secretary
// submits, Dean signs off, Registrar approves, Dean or Registrar rejects with a
// reason. Which controls show depends on the person's role and the status; the
// database enforces the same rules. Fewer than 5 students render as a list, 5
// or more as a table (ux-ui-guidelines.md).
import { useCallback, useEffect, useState } from 'react';
import { Button, Divider, Group, Modal, Select, Stack, Table, Text, TextInput, Title } from '@mantine/core';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import type { Role } from '@/lib/auth/roles';
import {
  approveSchedule,
  loadSectionDetail,
  moveStudent,
  rejectSchedule,
  saveLoading,
  signOffSchedule,
  submitSchedule,
  type ScheduleActionResult,
} from './actions';
import type { LoadingRow, PersonOption, RoomOption, SectionDetail, SectionRow, SectionStudent } from './queries';
import {
  DAY_LABEL,
  MAX_REASON,
  STATUS_LABEL,
  parseLoadingInput,
  parseReason,
  sectionLabel,
  subjectIsComplete,
  subjectName,
  windowLabel,
} from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

const DAY_OPTIONS = Object.entries(DAY_LABEL).map(([value, label]) => ({ value, label }));

type Draft = { professorId: string | null; roomId: string | null; day: string | null; start: string; end: string };

function draftOf(row: LoadingRow): Draft {
  return {
    professorId: row.professorId,
    roomId: row.roomId,
    day: row.dayOfWeek === null ? null : String(row.dayOfWeek),
    start: row.startTime ?? '',
    end: row.endTime ?? '',
  };
}

function isDirty(row: LoadingRow, draft: Draft): boolean {
  const saved = draftOf(row);
  return (Object.keys(saved) as (keyof Draft)[]).some((key) => saved[key] !== draft[key]);
}

function readOnlyLine(row: LoadingRow): string {
  const parts = [
    row.professorName ?? 'No professor',
    row.roomName ?? 'No room',
    row.dayOfWeek !== null && row.startTime && row.endTime
      ? `${DAY_LABEL[row.dayOfWeek]}, ${windowLabel(row.startTime, row.endTime)}`
      : 'No time',
  ];
  return parts.join(', ');
}

export function SectionDetailsModal({
  section,
  viewerRole,
  professors,
  rooms,
  sameProgramSections,
  onClose,
  onDone,
}: {
  section: SectionRow;
  viewerRole: Role;
  professors: PersonOption[];
  rooms: RoomOption[]; // already limited to rooms the section's college may use
  sameProgramSections: SectionRow[]; // other sections of the same program, for moving students
  onClose: () => void;
  onDone: (result: ScheduleActionResult) => void;
}) {
  const [detail, setDetail] = useState<SectionDetail | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState('');
  const [picks, setPicks] = useState<Record<string, string | null>>({});

  const isCollege = viewerRole === 'college_secretary' || viewerRole === 'dean' || viewerRole === 'admin';
  const isDean = viewerRole === 'dean' || viewerRole === 'admin';
  const isRegistrar = viewerRole === 'registrar' || viewerRole === 'admin';
  const status = section.status;

  const canEditLoading = isCollege && status === 'draft';
  const canSignOff = isDean && status === 'pending_dean';
  const canApprove = isRegistrar && status === 'dean_signed';
  const canReject = (isDean && status === 'pending_dean') || (isRegistrar && status === 'dean_signed');

  // Reads the rows and students again. Typed but unsaved changes survive a reload:
  // `reset` says which drafts to replace with what was saved ('all' on opening,
  // one row after saving it, 'none' after moving a student).
  const load = useCallback(
    async (reset: 'all' | 'none' | string) => {
      const result = await loadSectionDetail(section.id);
      if ('error' in result) {
        setError(result.error);
        return;
      }
      setDetail(result);
      setDrafts((current) =>
        Object.fromEntries(
          result.rows.map((row) => [
            row.id,
            reset === 'all' || reset === row.id || !current[row.id] ? draftOf(row) : current[row.id],
          ])
        )
      );
    },
    [section.id]
  );

  useEffect(() => {
    void load('all');
  }, [load]);

  const rows = detail?.rows ?? [];
  const students = detail?.students ?? [];
  const dirtyCount = rows.filter((row) => drafts[row.id] && isDirty(row, drafts[row.id])).length;
  const openCount = rows.filter((row) => !subjectIsComplete(row)).length;

  // Runs one action. A finished workflow step closes the modal; saving a row or
  // moving a student reloads it. Returns whether the action succeeded.
  async function run(
    key: string,
    action: () => Promise<ScheduleActionResult>,
    after: { close: true } | { reload: 'none' | string }
  ): Promise<boolean> {
    if (busy) return false;
    setBusy(key);
    setError(null);
    const result = await action();
    setBusy(null);
    if ('error' in result) {
      setError(result.error);
      return false;
    }
    if ('close' in after) {
      onDone(result);
    } else {
      await load(after.reload);
    }
    return true;
  }

  function inputFor(row: LoadingRow) {
    const draft = drafts[row.id] ?? draftOf(row);
    return parseLoadingInput({
      sectionSubjectId: row.id,
      professorId: draft.professorId,
      roomId: draft.roomId,
      dayOfWeek: draft.day === null ? null : Number(draft.day),
      startTime: draft.start,
      endTime: draft.end,
    });
  }

  function setDraft(row: LoadingRow, change: Partial<Draft>) {
    setDrafts((current) => ({ ...current, [row.id]: { ...(current[row.id] ?? draftOf(row)), ...change } }));
  }

  const submitBlock =
    dirtyCount > 0
      ? 'Save your changes first.'
      : rows.length === 0
        ? 'This section has no subjects yet.'
        : openCount > 0
          ? `${openCount} of ${rows.length} subjects still need a professor, room and time.`
          : null;

  const reasonCheck = parseReason(reason);
  const moveOptions = sameProgramSections.map((other) => ({
    value: other.id,
    label: `${sectionLabel(other.programCode, other.yearLevel, other.name)} (${other.studentCount} of ${other.capacity})`,
  }));

  function moveControl(student: SectionStudent) {
    return (
      <Group gap={spacing.sm} wrap="nowrap">
        <Select
          aria-label={`Move ${student.fullName} to section`}
          placeholder={moveOptions.length === 0 ? 'No other section' : 'Move to section'}
          data={moveOptions}
          value={picks[student.studentId] ?? null}
          onChange={(value) => setPicks((current) => ({ ...current, [student.studentId]: value }))}
          disabled={moveOptions.length === 0 || busy !== null}
        />
        <Button
          variant="default"
          size="xs"
          loading={busy === student.studentId}
          disabled={!picks[student.studentId] || busy !== null}
          onClick={() => {
            const target = picks[student.studentId];
            if (!target) return;
            void run(student.studentId, () => moveStudent(student.studentId, target), { reload: 'none' }).then((ok) => {
              if (ok) setPicks((current) => ({ ...current, [student.studentId]: null }));
            });
          }}
        >
          Move
        </Button>
      </Group>
    );
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title={sectionLabel(section.programCode, section.yearLevel, section.name)}
      padding={padding.modal}
      radius="lg"
      size="xl"
    >
      <Stack gap={spacing.md}>
        <Text size="sm" c={color.textSecondary}>
          {STATUS_LABEL[status]}, {section.studentCount} of {section.capacity} students
        </Text>
        {status === 'draft' && section.rejectedReason && (
          <Text size="sm" c={color.warning}>
            Sent back: {section.rejectedReason}
          </Text>
        )}

        <Divider />
        <Title order={4}>Subjects</Title>
        {!detail ? (
          <Text c={color.textSecondary}>Loading.</Text>
        ) : rows.length === 0 ? (
          <Text c={color.textSecondary}>No subjects for this program and year level yet.</Text>
        ) : (
          rows.map((row, index) => {
            const draft = drafts[row.id] ?? draftOf(row);
            const checked = inputFor(row);
            const dirty = isDirty(row, draft);
            return (
              <Stack key={row.id} gap={spacing.sm}>
                {index > 0 && <Divider />}
                <Group justify="space-between" wrap="nowrap">
                  <Text fw={fontWeight.semibold}>
                    {subjectName(row.code, row.meeting)}, {row.title}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {row.meeting === 'laboratory' ? 'No units' : `${row.units} units`}
                  </Text>
                </Group>
                {canEditLoading ? (
                  <Stack gap={spacing.sm}>
                    <Group grow gap={spacing.md} align="flex-start">
                      <Select
                        label="Professor"
                        placeholder={professors.length === 0 ? 'No professor accounts' : 'Choose'}
                        data={professors.map((p) => ({ value: p.id, label: p.fullName }))}
                        value={draft.professorId}
                        onChange={(value) => setDraft(row, { professorId: value })}
                        searchable
                        clearable
                        disabled={busy !== null}
                      />
                      <Select
                        label="Room"
                        placeholder={rooms.length === 0 ? 'No rooms' : 'Choose'}
                        data={rooms.map((r) => ({ value: r.id, label: r.name }))}
                        value={draft.roomId}
                        onChange={(value) => setDraft(row, { roomId: value })}
                        searchable
                        clearable
                        disabled={busy !== null}
                      />
                    </Group>
                    <Group grow gap={spacing.md} align="flex-start">
                      <Select
                        label="Day"
                        placeholder="Choose"
                        data={DAY_OPTIONS}
                        value={draft.day}
                        onChange={(value) => setDraft(row, { day: value })}
                        clearable
                        disabled={busy !== null}
                      />
                      <TextInput
                        label="Start time"
                        type="time"
                        value={draft.start}
                        onChange={(event) => setDraft(row, { start: event.currentTarget.value })}
                        disabled={busy !== null}
                      />
                      <TextInput
                        label="End time"
                        type="time"
                        value={draft.end}
                        onChange={(event) => setDraft(row, { end: event.currentTarget.value })}
                        disabled={busy !== null}
                      />
                    </Group>
                    {dirty && (
                      <Group justify="space-between">
                        <Text size="sm" c={checked.ok ? color.textSecondary : color.error}>
                          {checked.ok ? 'Unsaved changes.' : checked.reason}
                        </Text>
                        <Button
                          variant="default"
                          size="xs"
                          loading={busy === row.id}
                          disabled={!checked.ok || busy !== null}
                          onClick={() => {
                            if (checked.ok) void run(row.id, () => saveLoading(checked.value), { reload: row.id });
                          }}
                        >
                          Save
                        </Button>
                      </Group>
                    )}
                  </Stack>
                ) : (
                  <Text size="sm" c={color.textSecondary}>
                    {readOnlyLine(row)}
                  </Text>
                )}
              </Stack>
            );
          })
        )}

        <Divider />
        <Title order={4}>Students</Title>
        {!detail ? null : students.length === 0 ? (
          <Text c={color.textSecondary}>Nobody is placed in this section.</Text>
        ) : students.length < LIST_LIMIT ? (
          students.map((student, index) => (
            <Stack key={student.studentId} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between" wrap="nowrap">
                <Text>
                  {student.studentNumber}, {student.fullName}
                </Text>
                {isCollege && moveControl(student)}
              </Group>
            </Stack>
          ))
        ) : (
          <Table.ScrollContainer minWidth={640}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Student number</Table.Th>
                  <Table.Th>Student</Table.Th>
                  {isCollege && <Table.Th />}
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {students.map((student) => (
                  <Table.Tr key={student.studentId}>
                    <Table.Td>{student.studentNumber}</Table.Td>
                    <Table.Td>{student.fullName}</Table.Td>
                    {isCollege && <Table.Td>{moveControl(student)}</Table.Td>}
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

        {rejecting && (
          <Stack gap={spacing.sm}>
            <TextInput
              label="Reason"
              description="The Secretary sees this when the schedule is back in draft"
              maxLength={MAX_REASON}
              value={reason}
              onChange={(event) => setReason(event.currentTarget.value)}
              disabled={busy !== null}
              required
            />
            <Group justify="space-between">
              <Button
                variant="default"
                onClick={() => {
                  setRejecting(false);
                  setReason('');
                }}
                disabled={busy !== null}
              >
                Cancel
              </Button>
              <Button
                color="red"
                loading={busy === 'reject'}
                disabled={!reasonCheck.ok || busy !== null}
                onClick={() => {
                  if (reasonCheck.ok) void run('reject', () => rejectSchedule(section.id, reasonCheck.value), { close: true });
                }}
              >
                Send back to draft
              </Button>
            </Group>
          </Stack>
        )}

        {!rejecting && (canEditLoading || canSignOff || canApprove) && (
          <>
            <Divider />
            {canEditLoading && submitBlock && (
              <Text size="sm" c={color.textSecondary}>
                {submitBlock}
              </Text>
            )}
            <Group justify="space-between">
              <Group gap={spacing.sm}>
                {canReject && (
                  <Button variant="default" onClick={() => setRejecting(true)} disabled={busy !== null}>
                    Reject
                  </Button>
                )}
              </Group>
              {canEditLoading && (
                <Button
                  loading={busy === 'submit'}
                  disabled={submitBlock !== null || busy !== null}
                  onClick={() => void run('submit', () => submitSchedule(section.id), { close: true })}
                >
                  Submit for sign-off
                </Button>
              )}
              {canSignOff && (
                <Button
                  loading={busy === 'sign'}
                  disabled={busy !== null}
                  onClick={() => void run('sign', () => signOffSchedule(section.id), { close: true })}
                >
                  Sign off professor loading
                </Button>
              )}
              {canApprove && (
                <Button
                  loading={busy === 'approve'}
                  disabled={busy !== null}
                  onClick={() => void run('approve', () => approveSchedule(section.id), { close: true })}
                >
                  Approve schedule
                </Button>
              )}
            </Group>
          </>
        )}
      </Stack>
    </Modal>
  );
}
