'use client';

// The Registrar's documents page body: tabs, filters, and the list of
// applicants waiting to submit documents (or the students already received).
// Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). The checklist opens as a centered modal. All changes
// go through ./actions. Each Waiting and Received row has a Withdraw button
// (step 17); the Withdrawn tab lists who withdrew, who did it and why.
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Select, Stack, Table, Tabs, Text, TextInput } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { ProgramOption } from '@/features/visit-scheduling/queries';
import { formatSlotDate } from '@/features/visit-scheduling/schema';
import { WithdrawApplicantButton } from '@/features/withdraw-enrollment/WithdrawApplicantButton';
import { ChecklistModal } from './ChecklistModal';
import type { PendingApplicant, ReceivedStudent, WithdrawnApplicant } from './queries';
import {
  ADMISSION_TYPE_LABEL,
  MAX_SEARCH,
  formatReceivedDate,
  progressLabel,
  type DocumentsFilter,
  type DocumentsTab,
  type Requirement,
} from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table
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

  if (rows.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rows.map((row, index) => (
          <Stack key={row.applicantId} gap={spacing.sm}>
            {index > 0 && <Divider />}
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
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={900}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Applicant</Table.Th>
            <Table.Th>Reference</Table.Th>
            <Table.Th>Program</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th>Visit</Table.Th>
            <Table.Th>Required</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((row) => (
            <Table.Tr key={row.applicantId}>
              <Table.Td>{row.fullName}</Table.Td>
              <Table.Td>{row.applicantRef}</Table.Td>
              <Table.Td>{row.programCode}</Table.Td>
              <Table.Td>{ADMISSION_TYPE_LABEL[row.admissionType]}</Table.Td>
              <Table.Td>{visitText(row.visitDate)}</Table.Td>
              <Table.Td>{progressLabel(row.progress)}</Table.Td>
              <Table.Td>
                <Group justify="flex-end" gap={spacing.sm} wrap="nowrap">
                  <WithdrawApplicantButton applicantId={row.applicantId} name={row.fullName} identifier={row.applicantRef} />
                  <Button variant="default" size="xs" onClick={() => onOpen(row)}>
                    Open
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

function ReceivedRows({ rows, filtered }: { rows: ReceivedStudent[]; filtered: boolean }) {
  if (rows.length === 0) {
    return <Text c={color.textSecondary}>{filtered ? 'No students match.' : 'No documents received yet.'}</Text>;
  }

  if (rows.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rows.map((row, index) => (
          <Stack key={row.studentId} gap={spacing.xs}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {row.studentNumber}, {row.fullName}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {row.programCode}, {ADMISSION_TYPE_LABEL[row.admissionType]}, received {formatReceivedDate(row.receivedAt)}
                  {row.receivedByName ? ` by ${row.receivedByName}` : ''}
                </Text>
                {row.openLateItems.length > 0 && (
                  <Text size="sm" c={color.warning}>
                    Still to submit: {row.openLateItems.join('; ')}
                  </Text>
                )}
              </Stack>
              <WithdrawApplicantButton applicantId={row.applicantId} name={row.fullName} identifier={row.studentNumber} />
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={900}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Student number</Table.Th>
            <Table.Th>Student</Table.Th>
            <Table.Th>Program</Table.Th>
            <Table.Th>Received</Table.Th>
            <Table.Th>Received by</Table.Th>
            <Table.Th>Still to submit</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((row) => (
            <Table.Tr key={row.studentId}>
              <Table.Td>{row.studentNumber}</Table.Td>
              <Table.Td>{row.fullName}</Table.Td>
              <Table.Td>{row.programCode}</Table.Td>
              <Table.Td>{formatReceivedDate(row.receivedAt)}</Table.Td>
              <Table.Td>{row.receivedByName ?? ''}</Table.Td>
              <Table.Td>{row.openLateItems.join('; ')}</Table.Td>
              <Table.Td>
                <Group justify="flex-end">
                  <WithdrawApplicantButton applicantId={row.applicantId} name={row.fullName} identifier={row.studentNumber} />
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function WithdrawnRows({ rows, filtered }: { rows: WithdrawnApplicant[]; filtered: boolean }) {
  if (rows.length === 0) {
    return <Text c={color.textSecondary}>{filtered ? 'No one matches.' : 'Nobody has withdrawn.'}</Text>;
  }

  if (rows.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rows.map((row, index) => (
          <Stack key={row.applicantId} gap={spacing.xs}>
            {index > 0 && <Divider />}
            <Text fw={fontWeight.semibold}>
              {row.studentNumber ?? row.applicantRef}, {row.fullName}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {row.programCode}, {row.byStaff ? 'withdrawn by the Registrar' : 'withdrew themselves'} on {row.withdrawnOn}
            </Text>
            <Text size="sm" style={{ whiteSpace: 'pre-line' }}>
              Reason: {row.reason}
            </Text>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={900}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Person</Table.Th>
            <Table.Th>Number</Table.Th>
            <Table.Th>Program</Table.Th>
            <Table.Th>Withdrawn</Table.Th>
            <Table.Th>By</Table.Th>
            <Table.Th>Reason</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((row) => (
            <Table.Tr key={row.applicantId}>
              <Table.Td>{row.fullName}</Table.Td>
              <Table.Td>{row.studentNumber ?? row.applicantRef}</Table.Td>
              <Table.Td>{row.programCode}</Table.Td>
              <Table.Td>{row.withdrawnOn}</Table.Td>
              <Table.Td>{row.byStaff ? 'Registrar' : 'Themselves'}</Table.Td>
              <Table.Td style={{ whiteSpace: 'pre-line' }}>{row.reason}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
