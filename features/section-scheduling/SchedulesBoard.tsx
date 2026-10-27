'use client';

// The schedules page body, shared by the College Secretary / Dean page and the
// Registrar page: filters, students still waiting for a section, and the
// sections. Fewer than 5 sections render as a list, 5 or more as a table
// (ux-ui-guidelines.md). A section opens as a centered modal. All changes go
// through ./actions.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Select, Stack, Table, Tabs, Text, Title } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import type { Role } from '@/lib/auth/roles';
import { ReviewList } from '@/features/term-close/ReviewList';
import type { ReviewStudent } from '@/features/term-close/schema';
import { LoadModal } from '@/features/irregular-loads/LoadModal';
import type { LoadStudent } from '@/features/irregular-loads/schema';

// The role's own home page, as the "previous page" ancestor (matches the
// role's "Home" sidebar entry and the title its own home page shows).
const HOME_CRUMB: Record<Role, { label: string; href: string }> = {
  applicant: { label: 'Home', href: '/applicant' },
  student: { label: 'Home', href: '/student' },
  registrar: { label: 'Registrar', href: '/registrar' },
  finance: { label: 'Finance', href: '/finance' },
  dean: { label: 'Dean', href: '/dean' },
  college_secretary: { label: 'College Secretary', href: '/secretary' },
  professor: { label: 'Professor', href: '/professor' },
  admin: { label: 'Admin', href: '/admin' },
};
import { moveStudent, type ScheduleActionResult } from './actions';
import type { PersonOption, ProgramOption, RoomOption, SectionRow, WaitingStudent } from './queries';
import { SectionDetailsModal } from './SectionDetailsModal';
import { SectionFormModal } from './SectionFormModal';
import { STATUS_LABEL, sectionLabel, type ScheduleStatus } from './schema';

const LIST_LIMIT = 5;

const STATUS_OPTIONS = (Object.keys(STATUS_LABEL) as ScheduleStatus[]).map((value) => ({
  value,
  label: STATUS_LABEL[value],
}));

function subjectsText(section: SectionRow): string {
  return section.subjectCount === 0 ? 'No subjects yet' : `${section.readyCount} of ${section.subjectCount} ready`;
}

export function SchedulesBoard({
  viewerRole,
  basePath,
  programs,
  programId,
  status,
  sections,
  professors,
  rooms,
  waiting,
  tab = 'sections',
  review = [],
}: {
  viewerRole: Role;
  basePath: string;
  programs: ProgramOption[];
  programId: string | null;
  status: ScheduleStatus | null;
  sections: SectionRow[]; // every section the person can see; the filters apply here, move targets use all
  professors: PersonOption[];
  rooms: RoomOption[];
  waiting: WaitingStudent[];
  tab?: 'sections' | 'review'; // the Needs review tab is for the college staff only (step 21)
  review?: ReviewStudent[];
}) {
  const router = useRouter();
  const [message, setMessage] = useState<ScheduleActionResult | null>(null);
  const [form, setForm] = useState<{ section: SectionRow | null } | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const [picks, setPicks] = useState<Record<string, string | null>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [loadStudent, setLoadStudent] = useState<LoadStudent | null>(null);

  const isCollege = viewerRole === 'college_secretary' || viewerRole === 'dean' || viewerRole === 'admin';
  const visible = sections.filter(
    (section) => (!programId || section.programId === programId) && (!status || section.status === status)
  );
  const open = openId ? (sections.find((section) => section.id === openId) ?? null) : null;

  function setFilter(next: { program?: string | null; status?: string | null }) {
    const params = new URLSearchParams();
    const nextProgram = next.program === undefined ? programId : next.program;
    const nextStatus = next.status === undefined ? status : next.status;
    if (nextProgram) params.set('program', nextProgram);
    if (nextStatus) params.set('status', nextStatus);
    const query = params.toString();
    router.replace(query ? `${basePath}?${query}` : basePath);
  }

  function setTab(next: string | null) {
    setMessage(null);
    router.replace(next === 'review' ? `${basePath}?tab=review` : basePath);
  }

  function finish(result: ScheduleActionResult) {
    setForm(null);
    setOpenId(null);
    setMessage(result);
  }

  async function place(student: WaitingStudent) {
    const target = picks[student.studentId];
    if (!target || busy) return;
    setBusy(student.studentId);
    setMessage(null);
    const result = await moveStudent(student.studentId, target);
    setMessage(result);
    setBusy(null);
    if ('ok' in result) setPicks((current) => ({ ...current, [student.studentId]: null }));
  }

  // Rooms a section may use: no college set, or its own college (the database checks the same).
  const roomsFor = (section: SectionRow) =>
    rooms.filter((room) => room.collegeId === null || room.collegeId === section.collegeId);

  function rowActions(section: SectionRow) {
    return (
      <Group gap={spacing.sm} wrap="nowrap" justify="flex-end">
        <Button variant="default" size="xs" onClick={() => setOpenId(section.id)}>
          Open
        </Button>
        {isCollege && (
          <Button variant="default" size="xs" onClick={() => setForm({ section })}>
            Edit
          </Button>
        )}
      </Group>
    );
  }

  const tabs = isCollege ? (
    <Tabs value={tab} onChange={setTab}>
      <Tabs.List>
        <Tabs.Tab value="sections">Sections</Tabs.Tab>
        <Tabs.Tab value="review">{review.length > 0 ? `Needs review (${review.length})` : 'Needs review'}</Tabs.Tab>
      </Tabs.List>
    </Tabs>
  ) : null;

  // Students who did not pass everything in a closed term, with the reason (step 21).
  if (isCollege && tab === 'review') {
    return (
      <Stack gap={spacing.md}>
        <PageHeading title="Schedules" parent={HOME_CRUMB[viewerRole]} />
        {tabs}
        <Divider />
        <ReviewList
          students={review}
          onOpen={(student) =>
            setLoadStudent({ studentId: student.studentId, studentNumber: student.studentNumber, fullName: student.fullName })
          }
        />
        {loadStudent && <LoadModal student={loadStudent} onClose={() => setLoadStudent(null)} />}
      </Stack>
    );
  }

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between">
        <PageHeading title="Schedules" parent={HOME_CRUMB[viewerRole]} />
        {isCollege && (
          <Button onClick={() => setForm({ section: null })} disabled={programs.length === 0}>
            New section
          </Button>
        )}
      </Group>

      {tabs}

      <Group gap={spacing.md} align="flex-end">
        <Select
          label="Program"
          placeholder="All programs"
          data={programs.map((program) => ({ value: program.id, label: `${program.code} - ${program.name}` }))}
          value={programId}
          onChange={(value) => setFilter({ program: value })}
          searchable
          clearable
        />
        <Select
          label="Status"
          placeholder="All statuses"
          data={STATUS_OPTIONS}
          value={status}
          onChange={(value) => setFilter({ status: value })}
          clearable
        />
      </Group>

      <FormMessage message={message} />

      {isCollege && waiting.length > 0 && (
        <>
          <Divider />
          <Stack gap={spacing.md}>
            <Title order={4}>Waiting for a section</Title>
            {waiting.map((student, index) => {
              const options = sections
                .filter((section) => section.programId === student.programId)
                .map((section) => ({
                  value: section.id,
                  label: `${sectionLabel(section.programCode, section.yearLevel, section.name)} (${section.studentCount} of ${section.capacity})`,
                }));
              return (
                <Stack key={student.studentId} gap={spacing.sm}>
                  {index > 0 && <Divider />}
                  <Group justify="space-between" wrap="nowrap" align="flex-end">
                    <Stack gap={spacing.xs}>
                      <Text fw={fontWeight.semibold}>
                        {student.studentNumber}, {student.fullName}
                      </Text>
                      <Text size="sm" c={color.textSecondary}>
                        {student.programCode}
                      </Text>
                    </Stack>
                    <Group gap={spacing.sm} wrap="nowrap">
                      <Select
                        aria-label={`Section for ${student.fullName}`}
                        placeholder={options.length === 0 ? 'No section for this program' : 'Choose a section'}
                        data={options}
                        value={picks[student.studentId] ?? null}
                        onChange={(value) => setPicks((current) => ({ ...current, [student.studentId]: value }))}
                        disabled={options.length === 0 || busy !== null}
                      />
                      <Button
                        variant="default"
                        loading={busy === student.studentId}
                        disabled={!picks[student.studentId] || busy !== null}
                        onClick={() => void place(student)}
                      >
                        Place
                      </Button>
                    </Group>
                  </Group>
                </Stack>
              );
            })}
          </Stack>
        </>
      )}

      <Divider />

      {visible.length === 0 ? (
        <Text c={color.textSecondary}>{programId || status ? 'No sections match.' : 'No sections yet.'}</Text>
      ) : visible.length < LIST_LIMIT ? (
        <Stack gap={spacing.md}>
          {visible.map((section, index) => (
            <Stack key={section.id} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between" wrap="nowrap">
                <Stack gap={spacing.xs}>
                  <Text fw={fontWeight.semibold}>{sectionLabel(section.programCode, section.yearLevel, section.name)}</Text>
                  <Text size="sm" c={color.textSecondary}>
                    {STATUS_LABEL[section.status]}, subjects {subjectsText(section)}, {section.studentCount} of{' '}
                    {section.capacity} students
                  </Text>
                  {section.status === 'draft' && section.rejectedReason && (
                    <Text size="sm" c={color.warning}>
                      Sent back: {section.rejectedReason}
                    </Text>
                  )}
                </Stack>
                {rowActions(section)}
              </Group>
            </Stack>
          ))}
        </Stack>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Section</Table.Th>
                <Table.Th>Subjects</Table.Th>
                <Table.Th>Students</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {visible.map((section) => (
                <Table.Tr key={section.id}>
                  <Table.Td>{sectionLabel(section.programCode, section.yearLevel, section.name)}</Table.Td>
                  <Table.Td>{subjectsText(section)}</Table.Td>
                  <Table.Td>
                    {section.studentCount} of {section.capacity}
                  </Table.Td>
                  <Table.Td>
                    <Stack gap={spacing.xs}>
                      <Text size="sm">{STATUS_LABEL[section.status]}</Text>
                      {section.status === 'draft' && section.rejectedReason && (
                        <Text size="sm" c={color.warning}>
                          Sent back: {section.rejectedReason}
                        </Text>
                      )}
                    </Stack>
                  </Table.Td>
                  <Table.Td>{rowActions(section)}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {form && (
        <SectionFormModal
          section={form.section}
          programs={programs}
          defaultProgramId={programId}
          onClose={() => setForm(null)}
          onDone={finish}
        />
      )}

      {open && (
        <SectionDetailsModal
          section={open}
          viewerRole={viewerRole}
          professors={professors}
          rooms={roomsFor(open)}
          sameProgramSections={sections.filter((other) => other.programId === open.programId && other.id !== open.id)}
          onClose={() => setOpenId(null)}
          onDone={finish}
        />
      )}
    </Stack>
  );
}
