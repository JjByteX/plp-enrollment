'use client';

// The Prerequisites page body (step 20). One program at a time, one row per subject with the
// subjects it requires. Admin and the Dean edit; the Registrar and the Secretary only read.
// Fewer than 5 rows render as a list, 5 or more as a table (ux-ui-guidelines.md). Editing opens
// a centered modal. The chosen program lives in the address.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Select, Stack, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { FormMessage } from '@/components/FormMessage';
import { ListOrTable } from '@/components/ListOrTable';
import { SEMESTER_LABEL, yearLabel, type Semester } from '@/features/cor/schema';
import type { Role } from '@/lib/auth/roles';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { PrerequisiteActionResult } from './actions';
import { EditPrerequisitesModal } from './EditPrerequisitesModal';
import { canEditPrerequisites, prerequisiteText, type ProgramOption, type SubjectPrerequisites } from './schema';

const HOME: Partial<Record<Role, { label: string; href: string }>> = {
  registrar: { label: 'Registrar', href: '/registrar' },
  dean: { label: 'Dean', href: '/dean' },
  college_secretary: { label: 'College Secretary', href: '/secretary' },
  admin: { label: 'Admin', href: '/admin' },
};

function yearText(subject: SubjectPrerequisites): string {
  return subject.yearLevel === null ? 'No year level' : yearLabel(subject.yearLevel);
}

function semesterText(subject: SubjectPrerequisites): string {
  return SEMESTER_LABEL[subject.semester as Semester] ?? subject.semester;
}

export function PrerequisitesView({
  viewerRole,
  basePath,
  programs,
  programId,
  subjects,
}: {
  viewerRole: Role;
  basePath: string;
  programs: ProgramOption[];
  programId: string | null;
  subjects: SubjectPrerequisites[];
}) {
  const router = useRouter();
  const [message, setMessage] = useState<PrerequisiteActionResult | null>(null);
  const [editing, setEditing] = useState<SubjectPrerequisites | null>(null);

  const canEdit = canEditPrerequisites(viewerRole);
  const parent = HOME[viewerRole] ?? HOME.admin;

  function chooseProgram(value: string | null) {
    setMessage(null);
    router.replace(value ? `${basePath}?program=${value}` : basePath);
  }

  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Prerequisites" parent={parent} />

      <Select
        label="Program"
        data={programs.map((item) => ({ value: item.id, label: `${item.code}, ${item.name}` }))}
        value={programId}
        onChange={chooseProgram}
        searchable
        allowDeselect={false}
        disabled={programs.length === 0}
        w={400}
        maw="100%"
      />

      <FormMessage message={message} />

      <Divider />

      {programs.length === 0 ? (
        <Text c={color.textSecondary}>No program is available.</Text>
      ) : subjects.length === 0 ? (
        <Text c={color.textSecondary}>No subject is set up for this program.</Text>
      ) : (
        <ListOrTable
          rows={subjects}
          rowKey={(subject) => subject.subjectId}
          minWidth={720}
          item={(subject) => (
            <Group justify="space-between" wrap="nowrap" align="flex-start">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {subject.code}, {subject.title}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {yearText(subject)}, {semesterText(subject)}
                </Text>
                <Text size="sm">Requires: {prerequisiteText(subject)}</Text>
              </Stack>
              {canEdit && (
                <Button variant="default" onClick={() => setEditing(subject)}>
                  Edit
                </Button>
              )}
            </Group>
          )}
          columns={[
            { header: 'Year level', cell: yearText },
            { header: 'Semester', cell: semesterText },
            { header: 'Code', cell: (subject) => subject.code },
            { header: 'Title', cell: (subject) => subject.title },
            { header: 'Prerequisites', cell: prerequisiteText },
            {
              header: '',
              cell: (subject) =>
                canEdit ? (
                  <Group justify="flex-end">
                    <Button variant="default" size="xs" onClick={() => setEditing(subject)}>
                      Edit
                    </Button>
                  </Group>
                ) : null,
            },
          ]}
        />
      )}

      {editing && (
        <EditPrerequisitesModal
          subject={editing}
          subjects={subjects}
          onClose={() => setEditing(null)}
          onDone={(result) => {
            setEditing(null);
            setMessage(result);
            router.refresh();
          }}
        />
      )}
    </Stack>
  );
}
