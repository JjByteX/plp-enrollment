'use client';

// The Admin content page body: Subjects, Rooms and Term tabs. Fewer than 5
// rows render as a list, 5 or more as a table (ux-ui-guidelines.md). Adding
// and editing open a centered modal. The tab and the chosen program live in
// the URL. All changes go through ./actions.
import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Select, Stack, Table, Tabs, Text, TextInput } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import { SEMESTER_LABEL, termLabel, yearLabel, type Semester } from '@/features/cor/schema';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { saveTerm, type ContentActionResult } from './actions';
import type { CollegeOption, RoomRow, SubjectRow, TermRow } from './queries';
import { RoomModal } from './RoomModal';
import { SubjectModal } from './SubjectModal';
import { GradingTab } from '@/features/grading/GradingTab';
import type { Scale } from '@/features/grading/schema';
import { parseTermInput, type ContentTab } from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

const SEMESTER_OPTIONS = (Object.keys(SEMESTER_LABEL) as Semester[]).map((value) => ({
  value,
  label: SEMESTER_LABEL[value],
}));

export function ContentAdmin({
  tab,
  programs,
  programId,
  subjects,
  rooms,
  colleges,
  term,
  scale,
}: {
  tab: ContentTab;
  programs: ProgramOption[];
  programId: string | null;
  subjects: SubjectRow[];
  rooms: RoomRow[];
  colleges: CollegeOption[];
  term: TermRow | null;
  scale: Scale;
}) {
  const router = useRouter();
  const [message, setMessage] = useState<ContentActionResult | null>(null);
  const [subjectModal, setSubjectModal] = useState<{ subject: SubjectRow | null } | null>(null);
  const [roomModal, setRoomModal] = useState<{ room: RoomRow | null } | null>(null);

  const program = programs.find((item) => item.id === programId) ?? null;

  function go(nextTab: string | null, nextProgram?: string | null) {
    setMessage(null);
    const params = new URLSearchParams();
    if (nextTab && nextTab !== 'subjects') params.set('tab', nextTab);
    if (nextProgram) params.set('program', nextProgram);
    const query = params.toString();
    router.replace(query ? `/admin/content?${query}` : '/admin/content');
  }

  function done(result: ContentActionResult) {
    setSubjectModal(null);
    setRoomModal(null);
    setMessage(result);
  }

  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Content" parent={{ label: 'Admin', href: '/admin' }} />

      <Tabs value={tab} onChange={(value) => go(value, value === 'subjects' ? programId : null)}>
        <Tabs.List>
          <Tabs.Tab value="subjects">Subjects</Tabs.Tab>
          <Tabs.Tab value="rooms">Rooms</Tabs.Tab>
          <Tabs.Tab value="term">Term</Tabs.Tab>
          <Tabs.Tab value="grading">Grading</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <FormMessage message={message} />

      {tab === 'subjects' && (
        <>
          <Group justify="space-between" align="flex-end">
            <Select
              label="Program"
              data={programs.map((item) => ({ value: item.id, label: `${item.code}, ${item.name}` }))}
              value={programId}
              onChange={(value) => go('subjects', value)}
              searchable
              allowDeselect={false}
              w={400}
              maw="100%"
            />
            <Button disabled={!program} onClick={() => setSubjectModal({ subject: null })}>
              Add subject
            </Button>
          </Group>
          <Divider />
          <SubjectRows subjects={subjects} onEdit={(subject) => setSubjectModal({ subject })} />
        </>
      )}

      {tab === 'rooms' && (
        <>
          <Group justify="flex-end">
            <Button onClick={() => setRoomModal({ room: null })}>Add room</Button>
          </Group>
          <Divider />
          <RoomRows rooms={rooms} onEdit={(room) => setRoomModal({ room })} />
        </>
      )}

      {tab === 'term' && <TermForm term={term} onDone={setMessage} />}

      {tab === 'grading' && <GradingTab scale={scale} onDone={setMessage} />}

      {subjectModal && program && (
        <SubjectModal
          program={program}
          subject={subjectModal.subject}
          onClose={() => setSubjectModal(null)}
          onDone={done}
        />
      )}
      {roomModal && (
        <RoomModal room={roomModal.room} colleges={colleges} onClose={() => setRoomModal(null)} onDone={done} />
      )}
    </Stack>
  );
}

function SubjectRows({ subjects, onEdit }: { subjects: SubjectRow[]; onEdit: (subject: SubjectRow) => void }) {
  if (subjects.length === 0) return <Text c={color.textSecondary}>No subject is set up for this program.</Text>;

  const year = (subject: SubjectRow) => (subject.yearLevel === null ? 'None' : yearLabel(subject.yearLevel));
  const semesterText = (subject: SubjectRow) => SEMESTER_LABEL[subject.semester as Semester] ?? subject.semester;

  if (subjects.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {subjects.map((subject, index) => (
          <Stack key={subject.id} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {subject.code}, {subject.title}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {year(subject)}, {semesterText(subject)}, {subject.units} units
                  {subject.hasLaboratory ? ', with laboratory' : ''}
                  {subject.offeredInSummer ? ', also in summer' : ''}
                </Text>
              </Stack>
              <Button variant="default" onClick={() => onEdit(subject)}>
                Edit
              </Button>
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={720}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Year level</Table.Th>
            <Table.Th>Semester</Table.Th>
            <Table.Th>Code</Table.Th>
            <Table.Th>Title</Table.Th>
            <Table.Th>Units</Table.Th>
            <Table.Th>Laboratory</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {subjects.map((subject) => (
            <Table.Tr key={subject.id}>
              <Table.Td>{year(subject)}</Table.Td>
              <Table.Td>
                {semesterText(subject)}
                {subject.offeredInSummer ? ', also in summer' : ''}
              </Table.Td>
              <Table.Td>{subject.code}</Table.Td>
              <Table.Td>{subject.title}</Table.Td>
              <Table.Td>{subject.units}</Table.Td>
              <Table.Td>{subject.hasLaboratory ? 'Yes' : ''}</Table.Td>
              <Table.Td>
                <Group justify="flex-end">
                  <Button variant="default" size="xs" onClick={() => onEdit(subject)}>
                    Edit
                  </Button>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function RoomRows({ rooms, onEdit }: { rooms: RoomRow[]; onEdit: (room: RoomRow) => void }) {
  if (rooms.length === 0) return <Text c={color.textSecondary}>No room is set up yet.</Text>;

  if (rooms.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rooms.map((room, index) => (
          <Stack key={room.id} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>{room.name}</Text>
                <Text size="sm" c={color.textSecondary}>
                  {[room.capacity ? `${room.capacity} seats` : '', room.collegeCode].filter(Boolean).join(', ')}
                </Text>
              </Stack>
              <Button variant="default" onClick={() => onEdit(room)}>
                Edit
              </Button>
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={560}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Name</Table.Th>
            <Table.Th>Capacity</Table.Th>
            <Table.Th>College</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rooms.map((room) => (
            <Table.Tr key={room.id}>
              <Table.Td>{room.name}</Table.Td>
              <Table.Td>{room.capacity ?? ''}</Table.Td>
              <Table.Td>{room.collegeCode}</Table.Td>
              <Table.Td>
                <Group justify="flex-end">
                  <Button variant="default" size="xs" onClick={() => onEdit(room)}>
                    Edit
                  </Button>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function TermForm({ term, onDone }: { term: TermRow | null; onDone: (result: ContentActionResult) => void }) {
  const [schoolYear, setSchoolYear] = useState(term?.schoolYear ?? '');
  const [semester, setSemester] = useState<string | null>(term?.semester ?? null);
  const [loading, setLoading] = useState(false);

  const parsed = parseTermInput({ schoolYear, semester });
  const unchanged = term !== null && term.schoolYear === schoolYear.trim() && term.semester === semester;

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || loading) return;
    setLoading(true);
    onDone(await saveTerm(parsed.value));
    setLoading(false);
  }

  return (
    <form onSubmit={onSubmit}>
      <Stack gap={spacing.md} maw={400}>
        <Text c={color.textSecondary}>
          {term ? termLabel(term.schoolYear, term.semester) : 'No term is set. No section or COR can be made until one is.'}
        </Text>
        <TextInput
          label="School year"
          placeholder="2026-2027"
          value={schoolYear}
          onChange={(event) => setSchoolYear(event.currentTarget.value)}
          required
        />
        <Select label="Semester" data={SEMESTER_OPTIONS} value={semester} onChange={setSemester} required />
        {!parsed.ok && (
          <Text size="sm" c={color.textSecondary}>
            {parsed.reason}
          </Text>
        )}
        <Group justify="flex-end">
          <Button type="submit" loading={loading} disabled={!parsed.ok || unchanged}>
            Save term
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
