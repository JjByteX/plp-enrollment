'use client';

// The Grades page body for the Professor, the Dean and the Registrar (step 19):
// a Subjects tab with every section subject and its status, and a Changes tab
// with grade changes in flight. The Registrar's page also has the Close term control and a
// Completed tab (step 21). Fewer than 5 rows render as a list, 5 or more as
// a table (ux-ui-guidelines.md). A sheet opens as a centered modal. On the Registrar's page the
// Changes tab also lists the credits waiting for approval (step 20), and it has an On leave tab, a
// read-only list of students on leave of absence (step 23). On the Dean's page the Changes tab lists the
// leaves waiting for the Dean's decision.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Stack, Table, Tabs, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import type { Role } from '@/lib/auth/roles';
import { approveCredit, rejectCredit } from '@/features/prerequisites/actions';
import type { PendingCredit } from '@/features/prerequisites/schema';
import { LeaveRequestRows, OnLeaveList } from '@/features/leave-of-absence/LeaveRows';
import type { LeaveRequest, OnLeaveStudent } from '@/features/leave-of-absence/schema';
import { CloseTermBar } from '@/features/term-close/CloseTermBar';
import { CompletedList } from '@/features/term-close/CompletedList';
import type { CompletedStudent, TermStatus } from '@/features/term-close/schema';
import { approveChange, rejectChange, signChange, type GradingActionResult } from './actions';
import { ReasonDialog } from './ReasonModal';
import {
  KIND_LABEL,
  OUTCOME_LABEL,
  STATUS_LABEL,
  type GradeChange,
  type GradeSection,
  type GradeTab,
  type Sheet,
} from './schema';
import { SheetModal } from './SheetModal';

const LIST_LIMIT = 5;

const HOME: Partial<Record<Role, { label: string; href: string }>> = {
  registrar: { label: 'Registrar', href: '/registrar' },
  dean: { label: 'Dean', href: '/dean' },
  professor: { label: 'Professor', href: '/professor' },
  admin: { label: 'Admin', href: '/admin' },
};

export function GradesBoard({
  viewerRole,
  basePath,
  tab,
  sections,
  changes,
  sheet,
  ready,
  credits = [],
  termStatus = null,
  completed = [],
  leaves = [],
  onLeave = [],
}: {
  viewerRole: Role;
  basePath: string;
  tab: GradeTab;
  sections: GradeSection[];
  changes: GradeChange[];
  sheet: Sheet | null; // the sheet named in the address, when one is open
  ready: boolean;
  credits?: PendingCredit[]; // credits waiting for the Registrar; only that page passes them
  termStatus?: TermStatus | null; // the current term, for Close term; only the Registrar's page passes it
  completed?: CompletedStudent[]; // students who completed their program; only the Registrar's page passes them
  leaves?: LeaveRequest[]; // leaves waiting for the Dean; only the Dean's page passes them
  onLeave?: OnLeaveStudent[]; // students on leave; only the Registrar's page passes them
}) {
  const router = useRouter();
  const [message, setMessage] = useState<GradingActionResult | null>(null);
  const [rejecting, setRejecting] = useState<GradeChange | null>(null);
  const [rejectingCredit, setRejectingCredit] = useState<PendingCredit | null>(null);

  const parent = HOME[viewerRole] ?? HOME.admin;

  // Close term and the Completed tab belong to the Registrar and Admin, on the Registrar's page.
  const isRegistrar = (viewerRole === 'registrar' || viewerRole === 'admin') && termStatus !== null;
  const activeTab: GradeTab = (tab === 'completed' || tab === 'leave') && !isRegistrar ? 'sections' : tab;

  function setTab(next: string | null) {
    setMessage(null);
    router.replace(next === 'changes' || next === 'completed' || next === 'leave' ? `${basePath}?tab=${next}` : basePath);
  }

  function openSheet(section: GradeSection) {
    setMessage(null);
    router.replace(`${basePath}?section=${section.sectionId}&subject=${section.subjectId}`);
  }

  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Grades" parent={parent} />

      {isRegistrar && termStatus && (
        <>
          <CloseTermBar status={termStatus} onDone={setMessage} />
          <Divider />
        </>
      )}

      <Tabs value={activeTab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="sections">Subjects</Tabs.Tab>
          <Tabs.Tab value="changes">Changes</Tabs.Tab>
          {isRegistrar && <Tabs.Tab value="completed">Completed</Tabs.Tab>}
          {isRegistrar && <Tabs.Tab value="leave">On leave</Tabs.Tab>}
        </Tabs.List>
      </Tabs>

      <FormMessage message={message} />

      <Divider />

      {activeTab === 'sections' && <SectionRows sections={sections} onOpen={openSheet} />}
      {activeTab === 'completed' && <CompletedList students={completed} />}
      {activeTab === 'leave' && <OnLeaveList students={onLeave} />}
      {activeTab === 'changes' && (
        <ChangeRows
          changes={changes}
          credits={credits}
          leaves={leaves}
          viewerRole={viewerRole}
          onResult={setMessage}
          onReject={setRejecting}
          onRejectCredit={setRejectingCredit}
        />
      )}

      {sheet && (
        <SheetModal
          key={`${sheet.sectionId}-${sheet.subjectId}-${sheet.status}`}
          sheet={sheet}
          viewerRole={viewerRole}
          ready={ready}
          onClose={() => router.replace(basePath)}
          onDone={(result) => {
            setMessage(result);
            router.replace(basePath);
          }}
        />
      )}

      {rejecting && (
        <ReasonDialog
          title="Reject grade change"
          action="Reject"
          hint="The grade stays as it is. The Professor can propose another change."
          run={(reason) => rejectChange(rejecting.id, reason)}
          onClose={() => setRejecting(null)}
          onDone={(result) => {
            setRejecting(null);
            setMessage(result);
          }}
        />
      )}

      {rejectingCredit && (
        <ReasonDialog
          title="Reject credit"
          action="Reject"
          hint="The credit does not count as a pass. The Dean or the Secretary can record it again."
          run={(reason) => rejectCredit(rejectingCredit.id, reason)}
          onClose={() => setRejectingCredit(null)}
          onDone={(result) => {
            setRejectingCredit(null);
            setMessage(result);
          }}
        />
      )}
    </Stack>
  );
}

function progress(section: GradeSection): string {
  return `${STATUS_LABEL[section.status]}, ${section.graded} of ${section.students} graded`;
}

function SectionRows({ sections, onOpen }: { sections: GradeSection[]; onOpen: (section: GradeSection) => void }) {
  if (sections.length === 0) return <Text c={color.textSecondary}>No subject is open for grades this term.</Text>;

  if (sections.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {sections.map((section, index) => (
          <Stack key={`${section.sectionId}-${section.subjectId}`} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap" align="flex-start">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {section.label}, {section.code}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {section.title}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {[progress(section), section.professor].filter(Boolean).join(', ')}
                </Text>
              </Stack>
              <Button variant="default" onClick={() => onOpen(section)}>
                Open
              </Button>
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={640}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Section</Table.Th>
            <Table.Th>Subject</Table.Th>
            <Table.Th>Professor</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Graded</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {sections.map((section) => (
            <Table.Tr key={`${section.sectionId}-${section.subjectId}`}>
              <Table.Td>{section.label}</Table.Td>
              <Table.Td>
                {section.code}, {section.title}
              </Table.Td>
              <Table.Td>{section.professor ?? ''}</Table.Td>
              <Table.Td>{STATUS_LABEL[section.status]}</Table.Td>
              <Table.Td>
                {section.graded} of {section.students}
              </Table.Td>
              <Table.Td>
                <Button variant="default" size="xs" onClick={() => onOpen(section)}>
                  Open
                </Button>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function ChangeRows({
  changes,
  credits,
  leaves,
  viewerRole,
  onResult,
  onReject,
  onRejectCredit,
}: {
  changes: GradeChange[];
  credits: PendingCredit[];
  leaves: LeaveRequest[];
  viewerRole: Role;
  onResult: (result: GradingActionResult) => void;
  onReject: (change: GradeChange) => void;
  onRejectCredit: (credit: PendingCredit) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);

  // Only the Registrar and Admin decide on credits; nobody else is shown them.
  const decidesCredits = viewerRole === 'registrar' || viewerRole === 'admin';
  const waitingCredits = decidesCredits ? credits : [];
  // Only the Dean and Admin decide on leaves of absence (step 23).
  const decidesLeaves = viewerRole === 'dean' || viewerRole === 'admin';
  const waitingLeaves = decidesLeaves ? leaves : [];

  if (changes.length === 0 && waitingCredits.length === 0 && waitingLeaves.length === 0) {
    return (
      <Text c={color.textSecondary}>
        {decidesCredits
          ? 'No grade change or credit is waiting.'
          : decidesLeaves
            ? 'No grade change or leave is waiting.'
            : 'No grade change is waiting.'}
      </Text>
    );
  }

  async function decide(change: GradeChange) {
    if (busy) return;
    setBusy(change.id);
    const result = change.status === 'pending_dean' ? await signChange(change.id) : await approveChange(change.id);
    setBusy(null);
    onResult(result);
  }

  async function approve(credit: PendingCredit) {
    if (busy) return;
    setBusy(credit.id);
    const result = await approveCredit(credit.id);
    setBusy(null);
    onResult(result);
  }

  function canAct(change: GradeChange): boolean {
    if (viewerRole === 'admin') return true;
    if (change.status === 'pending_dean') return viewerRole === 'dean';
    return viewerRole === 'registrar';
  }

  return (
    <Stack gap={spacing.md}>
      {changes.map((change, index) => (
        <Stack key={change.id} gap={spacing.sm}>
          {index > 0 && <Divider />}
          <Group justify="space-between" wrap="nowrap" align="flex-start">
            <Stack gap={spacing.xs}>
              <Text fw={fontWeight.semibold}>
                {change.fullName} ({change.studentNumber})
              </Text>
              <Text size="sm" c={color.textSecondary}>
                {change.label}, {change.code}. {KIND_LABEL[change.kind]}.
              </Text>
              <Text size="sm">
                {change.oldGrade} ({OUTCOME_LABEL[change.oldOutcome]}) to {change.newGrade} ({OUTCOME_LABEL[change.newOutcome]})
              </Text>
              <Text size="sm" lineClamp={2}>
                {change.reason}
              </Text>
              <Text size="sm" c={color.textSecondary}>
                {change.status === 'pending_dean' ? 'Waiting for the Dean' : 'Waiting for the Registrar'}
                {change.proposedBy ? `, proposed by ${change.proposedBy}` : ''}
              </Text>
            </Stack>
            {canAct(change) && (
              <Group wrap="nowrap">
                <Button variant="default" disabled={busy !== null} onClick={() => onReject(change)}>
                  Reject
                </Button>
                <Button loading={busy === change.id} disabled={busy !== null && busy !== change.id} onClick={() => decide(change)}>
                  {change.status === 'pending_dean' ? 'Sign' : 'Approve'}
                </Button>
              </Group>
            )}
          </Group>
        </Stack>
      ))}
      {changes.length > 0 && waitingCredits.length > 0 && <Divider />}
      {waitingCredits.map((credit, index) => (
        <Stack key={credit.id} gap={spacing.sm}>
          {index > 0 && <Divider />}
          <Group justify="space-between" wrap="nowrap" align="flex-start">
            <Stack gap={spacing.xs}>
              <Text fw={fontWeight.semibold}>
                {credit.fullName} ({credit.studentNumber})
              </Text>
              <Text size="sm" c={color.textSecondary}>
                Credit for {credit.code}, {credit.title}. {credit.program}.
              </Text>
              <Text size="sm" lineClamp={2}>
                {credit.reason}
              </Text>
              <Text size="sm" c={color.textSecondary}>
                Waiting for the Registrar{credit.recordedBy ? `, recorded by ${credit.recordedBy}` : ''}
              </Text>
            </Stack>
            <Group wrap="nowrap">
              <Button variant="default" disabled={busy !== null} onClick={() => onRejectCredit(credit)}>
                Reject
              </Button>
              <Button loading={busy === credit.id} disabled={busy !== null && busy !== credit.id} onClick={() => approve(credit)}>
                Approve
              </Button>
            </Group>
          </Group>
        </Stack>
      ))}
      {(changes.length > 0 || waitingCredits.length > 0) && waitingLeaves.length > 0 && <Divider />}
      {waitingLeaves.length > 0 && <LeaveRequestRows requests={waitingLeaves} onResult={onResult} />}
    </Stack>
  );
}
