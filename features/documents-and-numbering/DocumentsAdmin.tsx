'use client';

// The Registrar's documents page body: tabs, filters, and the list of
// applicants waiting to submit documents (or the students already received).
// Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). The checklist opens as a centered modal. All changes
// go through ./actions. Each Waiting and Received row has a Withdraw button
// (step 17); the Withdrawn tab lists who withdrew, who did it and why. Each
// Received row also has a Correct button for a name or email fixed after
// promotion (features/correct-student-details).
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Select, Stack, Tabs, Text, TextInput } from '@mantine/core';
import { ListOrTable } from '@/components/ListOrTable';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { formatSlotDate, formatWeekdayDate } from '@/lib/format';
import { CorrectDetailsButton } from '@/features/correct-student-details/CorrectDetailsButton';
import { WithdrawApplicantButton } from '@/features/withdraw-enrollment/WithdrawApplicantButton';
import { ChecklistModal } from './ChecklistModal';
import type { PendingApplicant, ReceivedStudent, WithdrawnApplicant } from './queries';
import {
  ADMISSION_TYPE_LABEL,
  MAX_SEARCH,
  progressLabel,
  type DocumentsFilter,
  type DocumentsTab,
  type Requirement,
} from './schema';

const SEARCH_DELAY = 300;

function visitText(date: string | null): string {
  return date ? formatSlotDate(date) : 'No visit yet';
}

export function DocumentsAdmin({
  filter,
  programs,
  requirements,
  pending,
  received,
  withdrawn,
}: {
  filter: DocumentsFilter;
  programs: ProgramOption[];
  requirements: Requirement[];
  pending: PendingApplicant[];
  received: ReceivedStudent[];
  withdrawn: WithdrawnApplicant[];
}) {
  const router = useRouter();
  const [search, setSearch] = useState(filter.q);
  const [open, setOpen] = useState<PendingApplicant | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => () => clearTimeout(timer.current), []);

  function setFilter(next: { q?: string; program?: string | null; tab?: DocumentsTab }) {
    const params = new URLSearchParams();
    const q = next.q === undefined ? filter.q : next.q.trim();
    const program = next.program === undefined ? filter.programId : (next.program ?? undefined);
    const tab = next.tab ?? filter.tab;
    if (q) params.set('q', q);
    if (program) params.set('program', program);
    if (tab !== 'pending') params.set('tab', tab);
    const query = params.toString();
    router.replace(query ? `/registrar/documents?${query}` : '/registrar/documents');
  }

  function onSearch(value: string) {
    setSearch(value);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setFilter({ q: value }), SEARCH_DELAY);
  }

  // The list refreshes after each tick. Once an applicant becomes a student they
  // leave the list, so the open modal falls back to the snapshot it was opened with.
  const live = open ? (pending.find((row) => row.applicantId === open.applicantId) ?? null) : null;
  const filtered = filter.q !== '' || filter.programId !== undefined;

  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Documents" parent={{ label: 'Registrar', href: '/registrar' }} />

      <Tabs value={filter.tab} onChange={(value) => setFilter({ tab: value === 'received' || value === 'withdrawn' ? value : 'pending' })}>
        <Tabs.List>
          <Tabs.Tab value="pending">Waiting</Tabs.Tab>
          <Tabs.Tab value="received">Received</Tabs.Tab>
          <Tabs.Tab value="withdrawn">Withdrawn</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <Group gap={spacing.md} align="flex-end">
        <TextInput
          label="Search"
          placeholder={filter.tab === 'pending' ? 'Name, reference or email' : 'Name, reference or student number'}
          maxLength={MAX_SEARCH}
          value={search}
          onChange={(event) => onSearch(event.currentTarget.value)}
        />
        <Select
          label="Program"
          placeholder="All programs"
          data={programs.map((program) => ({ value: program.id, label: `${program.code} - ${program.name}` }))}
          value={filter.programId ?? null}
          onChange={(value) => setFilter({ program: value })}
          searchable
          clearable
        />
      </Group>

      <Divider />

      {filter.tab === 'pending' ? (
        <PendingRows rows={pending} filtered={filtered} onOpen={setOpen} />
      ) : filter.tab === 'received' ? (
        <ReceivedRows rows={received} filtered={filtered} />
      ) : (
        <WithdrawnRows rows={withdrawn} filtered={filtered} />
      )}

      {open && (
        <ChecklistModal
          applicant={live ?? open}
          requirements={requirements}
          onClose={() => setOpen(null)}
        />
      )}
    </Stack>
  );
}

function PendingRows({
  rows,
  filtered,
  onOpen,
}: {
  rows: PendingApplicant[];
  filtered: boolean;
  onOpen: (row: PendingApplicant) => void;
}) {
  if (rows.length === 0) {
    return (
      <Text c={color.textSecondary}>
        {filtered ? 'No applicants match.' : 'Nobody is waiting to submit documents.'}
      </Text>
    );
  }

  return (
    <ListOrTable
      rows={rows}
      rowKey={(row) => row.applicantId}
      minWidth={900}
      item={(row) => (
        <Group justify="space-between" wrap="nowrap">
          <Stack gap={spacing.xs}>
            <Text fw={fontWeight.semibold}>
              {row.fullName} ({row.applicantRef})
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {row.programCode}, {ADMISSION_TYPE_LABEL[row.admissionType]}, {visitText(row.visitDate)}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              Required documents: {progressLabel(row.progress)}
            </Text>
          </Stack>
          <Group gap={spacing.sm} wrap="nowrap">
            <WithdrawApplicantButton applicantId={row.applicantId} name={row.fullName} identifier={row.applicantRef} />
            <Button variant="default" onClick={() => onOpen(row)}>
              Open
            </Button>
          </Group>
        </Group>
      )}
      columns={[
        { header: 'Applicant', cell: (row) => row.fullName },
        { header: 'Reference', cell: (row) => row.applicantRef },
        { header: 'Program', cell: (row) => row.programCode },
        { header: 'Type', cell: (row) => ADMISSION_TYPE_LABEL[row.admissionType] },
        { header: 'Visit', cell: (row) => visitText(row.visitDate) },
        { header: 'Required', cell: (row) => progressLabel(row.progress) },
        {
          header: '',
          cell: (row) => (
            <Group justify="flex-end" gap={spacing.sm} wrap="nowrap">
              <WithdrawApplicantButton applicantId={row.applicantId} name={row.fullName} identifier={row.applicantRef} />
              <Button variant="default" size="xs" onClick={() => onOpen(row)}>
                Open
              </Button>
            </Group>
          ),
          sortable: false,
        },
      ]}
    />
  );
}

// The Correct and Withdraw buttons of a Received row, shared by its list and table forms.
function ReceivedButtons({ row }: { row: ReceivedStudent }) {
  return (
    <>
      <CorrectDetailsButton
        applicantId={row.applicantId}
        studentNumber={row.studentNumber}
        fullName={row.fullName}
        email={row.email}
      />
      <WithdrawApplicantButton applicantId={row.applicantId} name={row.fullName} identifier={row.studentNumber} />
    </>
  );
}

function ReceivedRows({ rows, filtered }: { rows: ReceivedStudent[]; filtered: boolean }) {
  if (rows.length === 0) {
    return <Text c={color.textSecondary}>{filtered ? 'No students match.' : 'No documents received yet.'}</Text>;
  }

  return (
    <ListOrTable
      rows={rows}
      rowKey={(row) => row.studentId}
      minWidth={900}
      itemGap={spacing.xs}
      item={(row) => (
        <Group justify="space-between" wrap="nowrap">
          <Stack gap={spacing.xs}>
            <Text fw={fontWeight.semibold}>
              {row.studentNumber}, {row.fullName}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {row.programCode}, {ADMISSION_TYPE_LABEL[row.admissionType]}, received {formatWeekdayDate(row.receivedAt)}
              {row.receivedByName ? ` by ${row.receivedByName}` : ''}
            </Text>
            {row.openLateItems.length > 0 && (
              <Text size="sm" c={color.warning}>
                Still to submit: {row.openLateItems.join('; ')}
              </Text>
            )}
          </Stack>
          <Group gap={spacing.sm} wrap="nowrap">
            <ReceivedButtons row={row} />
          </Group>
        </Group>
      )}
      columns={[
        { header: 'Student number', cell: (row) => row.studentNumber },
        { header: 'Student', cell: (row) => row.fullName },
        { header: 'Program', cell: (row) => row.programCode },
        { header: 'Received', cell: (row) => formatWeekdayDate(row.receivedAt), sortValue: (row) => row.receivedAt },
        { header: 'Received by', cell: (row) => row.receivedByName ?? '' },
        { header: 'Still to submit', cell: (row) => row.openLateItems.join('; ') },
        {
          header: '',
          cell: (row) => (
            <Group justify="flex-end" gap={spacing.sm} wrap="nowrap">
              <ReceivedButtons row={row} />
            </Group>
          ),
          sortable: false,
        },
      ]}
    />
  );
}

function WithdrawnRows({ rows, filtered }: { rows: WithdrawnApplicant[]; filtered: boolean }) {
  if (rows.length === 0) {
    return <Text c={color.textSecondary}>{filtered ? 'No one matches.' : 'Nobody has withdrawn.'}</Text>;
  }

  return (
    <ListOrTable
      rows={rows}
      rowKey={(row) => row.applicantId}
      minWidth={900}
      itemGap={spacing.xs}
      item={(row) => (
        <>
          <Text fw={fontWeight.semibold}>
            {row.studentNumber ?? row.applicantRef}, {row.fullName}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {row.programCode}, {row.byStaff ? 'withdrawn by the Registrar' : 'withdrew themselves'} on {row.withdrawnOn}
          </Text>
          <Text size="sm" style={{ whiteSpace: 'pre-line' }}>
            Reason: {row.reason}
          </Text>
        </>
      )}
      columns={[
        { header: 'Person', cell: (row) => row.fullName },
        { header: 'Number', cell: (row) => row.studentNumber ?? row.applicantRef },
        { header: 'Program', cell: (row) => row.programCode },
        { header: 'Withdrawn', cell: (row) => row.withdrawnOn },
        { header: 'By', cell: (row) => (row.byStaff ? 'Registrar' : 'Themselves') },
        { header: 'Reason', cell: (row) => row.reason, style: { whiteSpace: 'pre-line' } },
      ]}
    />
  );
}
