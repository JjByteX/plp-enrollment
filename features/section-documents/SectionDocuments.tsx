// features/section-documents/SectionDocuments.tsx
//
// The Sections page body: one row per section with how many students hold a
// slip and a COR, opening to the students and their status. The Registrar and
// Admin (canPrint) also get Print links for issued documents; the Dean and
// College Secretary only read. Presentational: the data comes from ./queries.
import { Accordion, Button, Group, Stack, Table, Text } from '@mantine/core';
import { PageHeading, type PageCrumb } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { SectionDocGroup, SectionDocStudent } from './queries';

function printUrl(path: string, students: SectionDocStudent[]): string {
  return `${path}?ids=${students.map((student) => student.studentId).join(',')}`;
}

function Status({ issued }: { issued: boolean }) {
  return (
    <Text size="sm" c={issued ? color.success : color.textSecondary}>
      {issued ? 'Issued' : 'Not yet'}
    </Text>
  );
}

export function SectionDocuments({
  groups,
  canPrint,
  parent,
}: {
  groups: SectionDocGroup[];
  canPrint: boolean;
  parent: PageCrumb;
}) {
  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Sections" parent={parent} />

      {groups.length === 0 ? (
        <Text c={color.textSecondary}>No student is placed in a section this term.</Text>
      ) : (
        <Accordion multiple variant="separated">
          {groups.map((group) => {
            const withSlip = group.students.filter((student) => student.slipIssued);
            const withCor = group.students.filter((student) => student.corIssued);
            return (
              <Accordion.Item key={group.sectionId} value={group.sectionId}>
                <Accordion.Control>
                  <Group justify="space-between" wrap="wrap" pr={spacing.md}>
                    <Text fw={fontWeight.semibold}>{group.section}</Text>
                    <Text size="sm" c={color.textSecondary}>
                      {group.students.length} students, {withSlip.length} slips, {withCor.length} CORs
                    </Text>
                  </Group>
                </Accordion.Control>
                <Accordion.Panel>
                  <Stack gap={spacing.md}>
                    {canPrint && (withSlip.length > 0 || withCor.length > 0) && (
                      <Group gap={spacing.sm}>
                        {withSlip.length > 0 && (
                          <Button component="a" href={printUrl('/print/slip', withSlip)} target="_blank" variant="default" size="xs">
                            Print slips ({withSlip.length})
                          </Button>
                        )}
                        {withCor.length > 0 && (
                          <Button component="a" href={printUrl('/print/cor', withCor)} target="_blank" variant="default" size="xs">
                            Print CORs ({withCor.length})
                          </Button>
                        )}
                      </Group>
                    )}
                    <Table.ScrollContainer minWidth={560}>
                      <Table>
                        <Table.Thead>
                          <Table.Tr>
                            <Table.Th>Student number</Table.Th>
                            <Table.Th>Student</Table.Th>
                            <Table.Th>Slip</Table.Th>
                            <Table.Th>COR</Table.Th>
                            {canPrint && <Table.Th />}
                          </Table.Tr>
                        </Table.Thead>
                        <Table.Tbody>
                          {group.students.map((student) => (
                            <Table.Tr key={student.studentId}>
                              <Table.Td>{student.studentNumber}</Table.Td>
                              <Table.Td>{student.fullName}</Table.Td>
                              <Table.Td>
                                <Status issued={student.slipIssued} />
                              </Table.Td>
                              <Table.Td>
                                <Status issued={student.corIssued} />
                              </Table.Td>
                              {canPrint && (
                                <Table.Td>
                                  <Group justify="flex-end" gap={spacing.sm} wrap="nowrap">
                                    {student.slipIssued && (
                                      <Button component="a" href={printUrl('/print/slip', [student])} target="_blank" variant="default" size="xs">
                                        Print slip
                                      </Button>
                                    )}
                                    {student.corIssued && (
                                      <Button component="a" href={printUrl('/print/cor', [student])} target="_blank" variant="default" size="xs">
                                        Print COR
                                      </Button>
                                    )}
                                  </Group>
                                </Table.Td>
                              )}
                            </Table.Tr>
                          ))}
                        </Table.Tbody>
                      </Table>
                    </Table.ScrollContainer>
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
            );
          })}
        </Accordion>
      )}
    </Stack>
  );
}
