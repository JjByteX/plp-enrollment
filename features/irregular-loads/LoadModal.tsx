'use client';

// One student's load in a centered modal, opened from the Needs review list (step 22). The
// Secretary or the Dean sees every subject of the student's program by where the student stands:
// already in the load, allowed (with the sections of this term that offer it), blocked (with the
// prerequisite named), already passed, or not offered this term. A student with no section yet is
// placed first. A subject is added from any section of the current term that offers it. The
// database refuses a blocked subject for every role, so the screen only explains it. A Credits
// button opens the credits window of step 20, so a transferee can be credited from here, and a
// Leave button opens the leave of absence window of step 23. Once the
// assessment slip is issued the load is fixed and the controls are hidden.
import { useCallback, useEffect, useState } from 'react';
import { Button, Divider, Group, Modal, Select, Stack, Text, Title } from '@mantine/core';
import { FormMessage, type FormMessageValue } from '@/components/FormMessage';
import { termLabel } from '@/features/cor/schema';
import { LeaveModal } from '@/features/leave-of-absence/LeaveModal';
import { CreditsModal } from '@/features/prerequisites/CreditsModal';
import { moveStudent } from '@/features/section-scheduling/actions';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import { addSubjectToLoad, loadStudentLoad, removeSubjectFromLoad } from './actions';
import {
  blockedText,
  optionFull,
  optionLabel,
  type LoadStudent,
  type LoadSubject,
  type SectionOption,
  type StudentLoad,
} from './schema';

function codes(subjects: LoadSubject[]): string {
  return subjects.map((subject) => subject.code).join(', ');
}

export function LoadModal({ student, onClose }: { student: LoadStudent; onClose: () => void }) {
  const [load, setLoad] = useState<StudentLoad | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [message, setMessage] = useState<FormMessageValue | null>(null);
  const [picks, setPicks] = useState<Record<string, string | null>>({});
  const [placePick, setPlacePick] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [credits, setCredits] = useState(false);
  const [leave, setLeave] = useState(false);

  const reload = useCallback(async () => {
    const result = await loadStudentLoad(student.studentId);
    if ('error' in result) setLoadError(result.error);
    else {
      setLoadError(null);
      setLoad(result);
    }
  }, [student.studentId]);

  useEffect(() => {
    void reload();
  }, [reload]);

  // Runs one change, shows what happened and reads the load again so the groups are current.
  async function change(key: string, action: () => Promise<{ ok: true; message: string } | { error: string }>) {
    if (busy) return;
    setBusy(key);
    setMessage(null);
    const result = await action();
    setMessage(result);
    if ('ok' in result) await reload();
    setBusy(null);
  }

  function place() {
    if (!placePick) return;
    void change('place', () => moveStudent(student.studentId, placePick));
  }

  function add(subject: LoadSubject) {
    const sectionId = picks[subject.subjectId];
    if (!sectionId) return;
    void change(`add-${subject.subjectId}`, () =>
      addSubjectToLoad({ studentId: student.studentId, sectionId, subjectId: subject.subjectId })
    );
  }

  function remove(subject: LoadSubject) {
    void change(`remove-${subject.subjectId}`, () => removeSubjectFromLoad(student.studentId, subject.subjectId));
  }

  const inLoad = load?.subjects.filter((subject) => subject.status === 'in_load') ?? [];
  const allowed = load?.subjects.filter((subject) => subject.status === 'allowed') ?? [];
  const blocked = load?.subjects.filter((subject) => subject.status === 'blocked') ?? [];
  const passed = load?.subjects.filter((subject) => subject.status === 'passed') ?? [];
  const notOffered = load?.subjects.filter((subject) => subject.status === 'not_offered') ?? [];
  const editable = load !== null && load.enrolled && !load.locked;

  const sectionData = (options: SectionOption[]) =>
    options.map((option) => ({ value: option.sectionId, label: optionLabel(option), disabled: optionFull(option) }));

  return (
    <Modal opened onClose={onClose} title={`Load, ${student.fullName}`} padding={padding.modal} radius="lg" size="xl">
      <Stack gap={spacing.md}>
        <Text size="sm" c={color.textSecondary}>
          {student.studentNumber}
          {load ? `, ${load.programCode}, ${termLabel(load.schoolYear, load.semester)}` : ''}
        </Text>

        {loadError ? (
          <Text size="sm" c={color.error} role="alert">
            {loadError}
          </Text>
        ) : load === null ? (
          <Text c={color.textSecondary}>Loading.</Text>
        ) : (
          <>
            <FormMessage message={message} />

            {!load.enrolled ? (
              <Stack gap={spacing.sm}>
                <Text>This student has no section in this term yet. Place the student first, then build the load.</Text>
                <Group gap={spacing.sm} align="flex-end" wrap="nowrap">
                  <Select
                    aria-label="Section"
                    placeholder={load.places.length === 0 ? 'No section for this program' : 'Choose a section'}
                    data={sectionData(load.places)}
                    value={placePick}
                    onChange={setPlacePick}
                    disabled={load.places.length === 0 || busy !== null}
                  />
                  <Button
                    variant="default"
                    loading={busy === 'place'}
                    disabled={!placePick || busy !== null}
                    onClick={place}
                  >
                    Place
                  </Button>
                </Group>
              </Stack>
            ) : (
              <>
                <Text size="sm" c={color.textSecondary}>
                  Placed in {load.section}
                </Text>
                {load.locked && (
                  <Text size="sm" c={color.warning}>
                    The assessment slip was already issued, so the load can no longer be changed.
                  </Text>
                )}

                <Divider />
                <Title order={4}>In the load</Title>
                {inLoad.length === 0 ? (
                  <Text c={color.textSecondary}>No subject yet.</Text>
                ) : (
                  <Stack gap={spacing.sm}>
                    {inLoad.map((subject) => (
                      <Group key={subject.subjectId} justify="space-between" wrap="nowrap">
                        <Stack gap={spacing.xs}>
                          <Text fw={fontWeight.semibold}>
                            {subject.code}, {subject.title}
                          </Text>
                          <Text size="sm" c={color.textSecondary}>
                            {subject.takenIn}
                            {subject.source === 'added' ? ', added by staff' : ''}
                          </Text>
                        </Stack>
                        {editable && subject.source === 'added' && (
                          <Button
                            variant="default"
                            size="xs"
                            loading={busy === `remove-${subject.subjectId}`}
                            disabled={busy !== null}
                            onClick={() => remove(subject)}
                          >
                            Remove
                          </Button>
                        )}
                      </Group>
                    ))}
                  </Stack>
                )}

                {allowed.length > 0 && (
                  <>
                    <Divider />
                    <Title order={4}>Can be added</Title>
                    <Stack gap={spacing.sm}>
                      {allowed.map((subject) => (
                        <Group key={subject.subjectId} justify="space-between" wrap="nowrap" align="flex-end">
                          <Stack gap={spacing.xs}>
                            <Text fw={fontWeight.semibold}>
                              {subject.code}, {subject.title}
                            </Text>
                            <Text size="sm" c={color.textSecondary}>
                              Year {subject.yearLevel}, {subject.semester} semester
                            </Text>
                          </Stack>
                          {editable && (
                            <Group gap={spacing.sm} wrap="nowrap">
                              <Select
                                aria-label={`Section for ${subject.code}`}
                                placeholder="Choose a section"
                                data={sectionData(subject.options)}
                                value={picks[subject.subjectId] ?? null}
                                onChange={(value) => setPicks((current) => ({ ...current, [subject.subjectId]: value }))}
                                disabled={busy !== null}
                              />
                              <Button
                                variant="default"
                                loading={busy === `add-${subject.subjectId}`}
                                disabled={!picks[subject.subjectId] || busy !== null}
                                onClick={() => add(subject)}
                              >
                                Add
                              </Button>
                            </Group>
                          )}
                        </Group>
                      ))}
                    </Stack>
                  </>
                )}

                {blocked.length > 0 && (
                  <>
                    <Divider />
                    <Title order={4}>Blocked</Title>
                    <Stack gap={spacing.sm}>
                      {blocked.map((subject) => (
                        <Stack key={subject.subjectId} gap={spacing.xs}>
                          <Text fw={fontWeight.semibold}>
                            {subject.code}, {subject.title}
                          </Text>
                          <Text size="sm" c={color.textSecondary}>
                            {blockedText(subject)}
                          </Text>
                        </Stack>
                      ))}
                    </Stack>
                  </>
                )}

                {(passed.length > 0 || notOffered.length > 0) && (
                  <>
                    <Divider />
                    {passed.length > 0 && (
                      <Text size="sm" c={color.textSecondary}>
                        Already passed or credited: {codes(passed)}.
                      </Text>
                    )}
                    {notOffered.length > 0 && (
                      <Text size="sm" c={color.textSecondary}>
                        Not offered this term: {codes(notOffered)}.
                      </Text>
                    )}
                  </>
                )}
              </>
            )}
          </>
        )}

        <Group justify="space-between">
          <Group gap={spacing.sm}>
            <Button variant="default" onClick={() => setCredits(true)} disabled={busy !== null || load === null}>
              Credits
            </Button>
            <Button variant="default" onClick={() => setLeave(true)} disabled={busy !== null || load === null}>
              Leave
            </Button>
          </Group>
          <Button variant="default" onClick={onClose} disabled={busy !== null}>
            Close
          </Button>
        </Group>
      </Stack>

      {leave && (
        <LeaveModal
          student={student}
          onClose={() => setLeave(false)}
          onDone={(result) => {
            setLeave(false);
            setMessage(result);
          }}
        />
      )}
      {credits && (
        <CreditsModal
          student={student}
          onClose={() => setCredits(false)}
          onDone={(result) => {
            setCredits(false);
            setMessage(result);
            void reload();
          }}
        />
      )}
    </Modal>
  );
}
