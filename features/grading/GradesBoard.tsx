'use client';

// The Grades page body for the Professor, the Dean and the Registrar (step 19):
// a Subjects tab with every section subject and its status, and a Changes tab
// with grade changes in flight. Fewer than 5 rows render as a list, 5 or more as
// a table (ux-ui-guidelines.md). A sheet opens as a centered modal.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Stack, Table, Tabs, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import type { Role } from '@/lib/auth/roles';
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
}: {
  viewerRole: Role;
  basePath: string;
  tab: GradeTab;
  sections: GradeSection[];
  changes: GradeChange[];
  sheet: Sheet | null; // the sheet named in the address, when one is open
  ready: boolean;
}) {
  const router = useRouter();
  const [message, setMessage] = useState<GradingActionResult | null>(null);
  const [rejecting, setRejecting] = useState<GradeChange | null>(null);

  const parent = HOME[viewerRole] ?? HOME.admin;

  function setTab(next: string | null) {
    setMessage(null);
    router.replace(next === 'changes' ? `${basePath}?tab=changes` : basePath);
  }

  function openSheet(section: GradeSection) {
    setMessage(null);
    router.replace(`${basePath}?section=${section.sectionId}&subject=${section.subjectId}`);
  }

  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Grades" parent={parent} />

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="sections">Subjects</Tabs.Tab>
          <Tabs.Tab value="changes">Changes</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <FormMessage message={message} />

      <Divider />

      {tab === 'sections' && <SectionRows sections={sections} onOpen={openSheet} />}
      {tab === 'changes' && <ChangeRows changes={changes} viewerRole={viewerRole} onResult={setMessage} onReject={setRejecting} />}

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
  viewerRole,
  onResult,
  onReject,
}: {
  changes: GradeChange[];
  viewerRole: Role;
  onResult: (result: GradingActionResult) => void;
  onReject: (change: GradeChange) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);

  if (changes.length === 0) return <Text c={color.textSecondary}>No grade change is waiting.</Text>;

  async function decide(change: GradeChange) {
    if (busy) return;
    setBusy(change.id);
    const result = change.status === 'pending_dean' ? await signChange(change.id) : await approveChange(change.id);
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
    </Stack>
  );
}
