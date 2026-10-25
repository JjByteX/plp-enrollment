'use client';

// The Professor's home: their subjects in approved schedules and the class
// list of each (name and student number only). Fewer than 5 rows render as a
// list, 5 or more as a table (ux-ui-guidelines.md). The class list opens in a
// centered modal. Read only.
import { useState } from 'react';
import { Button, Divider, Group, Modal, Stack, Table, Text, Title } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { ClassStudent, LoadRow } from './queries';

const LIST_LIMIT = 5;

export function ProfessorLoad({ rows, students }: { rows: LoadRow[]; students: ClassStudent[] }) {
  const [open, setOpen] = useState<LoadRow | null>(null);
  const classList = open
    ? students.filter((student) => student.sectionId === open.sectionId && student.subjectCode === open.subjectCode)
    : [];

  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Professor</Title>

      {rows.length === 0 ? (
        <Text c={color.textSecondary}>No subjects are assigned to you yet.</Text>
      ) : rows.length < LIST_LIMIT ? (
        <Stack gap={spacing.md}>
          {rows.map((row, index) => (
            <Stack key={row.id} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between" wrap="nowrap">
                <Stack gap={spacing.xs}>
                  <Text fw={fontWeight.semibold}>
                    {row.subject}, {row.title}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {row.section}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {[row.schedule, row.room].filter(Boolean).join(', ')}
                  </Text>
                </Stack>
                <Button variant="default" onClick={() => setOpen(row)}>
                  Class list
                </Button>
              </Group>
            </Stack>
          ))}
        </Stack>
      ) : (
        <Table.ScrollContainer minWidth={720}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Subject</Table.Th>
                <Table.Th>Section</Table.Th>
                <Table.Th>Schedule</Table.Th>
                <Table.Th>Room</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((row) => (
                <Table.Tr key={row.id}>
                  <Table.Td>
                    {row.subject}, {row.title}
                  </Table.Td>
                  <Table.Td>{row.section}</Table.Td>
                  <Table.Td>{row.schedule}</Table.Td>
                  <Table.Td>{row.room}</Table.Td>
                  <Table.Td>
                    <Group justify="flex-end">
                      <Button variant="default" size="xs" onClick={() => setOpen(row)}>
                        Class list
                      </Button>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      <Modal
        opened={open !== null}
        onClose={() => setOpen(null)}
        title={open ? `${open.subject}, ${open.section}` : ''}
        centered
      >
        {classList.length === 0 ? (
          <Text c={color.textSecondary}>No students are placed in this section yet.</Text>
        ) : classList.length < LIST_LIMIT ? (
          <Stack gap={spacing.sm}>
            {classList.map((student) => (
              <Text key={student.studentNumber}>
                {student.studentNumber}, {student.fullName}
              </Text>
            ))}
          </Stack>
        ) : (
          <Table.ScrollContainer minWidth={360}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Student number</Table.Th>
                  <Table.Th>Name</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {classList.map((student) => (
                  <Table.Tr key={student.studentNumber}>
                    <Table.Td>{student.studentNumber}</Table.Td>
                    <Table.Td>{student.fullName}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Modal>
    </Stack>
  );
}
