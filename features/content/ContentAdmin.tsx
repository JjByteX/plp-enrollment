'use client';

// The Admin content page body: Subjects, Rooms and Term tabs. Fewer than 5
// rows render as a list, 5 or more as a table (ux-ui-guidelines.md). Adding,
// editing and importing subjects open a centered modal; Download saves the
// program's subjects as a CSV file in the import layout. The tab and the chosen program live in
// the URL. All changes go through ./actions.
import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Select, Stack, Tabs, Text, TextInput } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import { ListOrTable } from '@/components/ListOrTable';
import { SEMESTER_LABEL, termLabel, yearLabel, type Semester } from '@/features/cor/schema';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { saveTerm, type ContentActionResult } from './actions';
import type { CollegeOption, RoomRow, SubjectRow, TermRow } from './queries';
import { downloadSubjectsCsv } from './exportSubjects';
import { RoomModal } from './RoomModal';
import { SubjectImportModal } from './SubjectImportModal';
import { SubjectModal } from './SubjectModal';
import { GradingTab } from '@/features/grading/GradingTab';
import type { Scale } from '@/features/grading/schema';
import { parseTermInput, type ContentTab } from './schema';

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
  const [importOpen, setImportOpen] = useState(false);
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
    setImportOpen(false);
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
            <Group gap={spacing.sm}>
              <Button
                variant="default"
                disabled={!program || subjects.length === 0}
                onClick={() => program && downloadSubjectsCsv(program.code, subjects)}
              >
                Download
              </Button>
              <Button variant="default" disabled={!program} onClick={() => setImportOpen(true)}>
                Import
              </Button>
              <Button disabled={!program} onClick={() => setSubjectModal({ subject: null })}>
                Add subject
              </Button>
            </Group>
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
      {importOpen && program && (
        <SubjectImportModal
          program={program}
          existingCodes={subjects.map((subject) => subject.code)}
          onClose={() => setImportOpen(false)}
          onDone={done}
        />
      )}
      {roomModal && (
        <RoomModal room={roomModal.room} colleges={colleges} onClose={() => setRoomModal(null)} onDone={done} />
      )}
    </Stack>
  );
}

// Semester's display order (1st, 2nd, summer) isn't its alphabetical order,
// so sorting the Semester column needs this explicit rank rather than the
// label text or the raw code.
const SEMESTER_ORDER: Record<string, number> = Object.fromEntries(
  (Object.keys(SEMESTER_LABEL) as Semester[]).map((value, index) => [value, index]),
);

function SubjectRows({ subjects, onEdit }: { subjects: SubjectRow[]; onEdit: (subject: SubjectRow) => void }) {
  if (subjects.length === 0) return <Text c={color.textSecondary}>No subject is set up for this program.</Text>;

  const year = (subject: SubjectRow) => (subject.yearLevel === null ? 'None' : yearLabel(subject.yearLevel));
  const semesterText = (subject: SubjectRow) => SEMESTER_LABEL[subject.semester as Semester] ?? subject.semester;

  return (
    <ListOrTable
      rows={subjects}
      rowKey={(subject) => subject.id}
      minWidth={720}
      item={(subject) => (
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
      )}
      columns={[
        {
          header: 'Year level',
          cell: year,
          // null (no year level) sorts last, same as the server's own
          // `order('year_level', { nullsFirst: false })`.
          sortValue: (subject) => subject.yearLevel ?? Number.MAX_SAFE_INTEGER,
        },
        {
          header: 'Semester',
          cell: (subject) => (
            <>
              {semesterText(subject)}
              {subject.offeredInSummer ? ', also in summer' : ''}
            </>
          ),
          sortValue: (subject) => SEMESTER_ORDER[subject.semester] ?? subject.semester,
        },
        { header: 'Code', cell: (subject) => subject.code },
        { header: 'Title', cell: (subject) => subject.title },
        { header: 'Units', cell: (subject) => subject.units },
        { header: 'Laboratory', cell: (subject) => (subject.hasLaboratory ? 'Yes' : ''), sortValue: (subject) => (subject.hasLaboratory ? 1 : 0) },
        {
          header: '',
          cell: (subject) => (
            <Group justify="flex-end">
              <Button variant="default" size="xs" onClick={() => onEdit(subject)}>
                Edit
              </Button>
            </Group>
          ),
          sortable: false,
        },
      ]}
    />
  );
}

function RoomRows({ rooms, onEdit }: { rooms: RoomRow[]; onEdit: (room: RoomRow) => void }) {
  if (rooms.length === 0) return <Text c={color.textSecondary}>No room is set up yet.</Text>;

  return (
    <ListOrTable
      rows={rooms}
      rowKey={(room) => room.id}
      minWidth={560}
      item={(room) => (
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
      )}
      columns={[
        { header: 'Name', cell: (room) => room.name },
        { header: 'Capacity', cell: (room) => room.capacity ?? '', sortValue: (room) => room.capacity ?? -1 },
        { header: 'College', cell: (room) => room.collegeCode },
        {
          header: '',
          cell: (room) => (
            <Group justify="flex-end">
              <Button variant="default" size="xs" onClick={() => onEdit(room)}>
                Edit
              </Button>
            </Group>
          ),
          sortable: false,
        },
      ]}
    />
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
