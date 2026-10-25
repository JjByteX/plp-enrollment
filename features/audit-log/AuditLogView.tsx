'use client';

// The Admin's audit log page body. Read only: the log is append only, so
// nothing here changes data. Filters and the page number live in the URL, so
// the server reads the right page. Fewer than 5 rows render as a list, 5 or
// more as a table (ux-ui-guidelines.md). Details open in a centered modal.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Modal, Pagination, Select, Stack, Table, Text, Title } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { ROLE_LABEL, isRole } from '@/lib/auth/roles';
import type { AuditEntry } from './queries';
import {
  ACTION_LABEL,
  AUDIT_ACTIONS,
  AUDIT_TABLE_LABEL,
  PAGE_SIZE,
  auditHref,
  changedFields,
  tableLabel,
  type AuditAction,
  type AuditFilters,
} from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

export type AuditRow = AuditEntry & { when: string }; // when: formatted on the server

function actionLabel(action: string): string {
  return ACTION_LABEL[action as AuditAction] ?? action;
}

function actorText(row: AuditRow): string {
  const role = row.actorRole && isRole(row.actorRole) ? ROLE_LABEL[row.actorRole] : row.actorRole;
  return role ? `${row.actorName} (${role})` : row.actorName;
}

const TABLE_OPTIONS = Object.entries(AUDIT_TABLE_LABEL).map(([value, label]) => ({ value, label }));
const ACTION_OPTIONS = AUDIT_ACTIONS.map((value) => ({ value, label: ACTION_LABEL[value] }));

export function AuditLogView({
  rows,
  total,
  filters,
}: {
  rows: AuditRow[];
  total: number;
  filters: AuditFilters;
}) {
  const router = useRouter();
  const [open, setOpen] = useState<AuditRow | null>(null);
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  function go(next: Partial<AuditFilters>) {
    // A new filter starts again at page 1.
    router.push(auditHref({ ...filters, page: 1, ...next }));
  }

  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Audit log</Title>

      <Group gap={spacing.md} align="flex-end">
        <Select
          label="Table"
          placeholder="All tables"
          data={TABLE_OPTIONS}
          value={filters.table}
          clearable
          searchable
          onChange={(value) => go({ table: value })}
        />
        <Select
          label="Action"
          placeholder="All actions"
          data={ACTION_OPTIONS}
          value={filters.action}
          clearable
          onChange={(value) => go({ action: value as AuditAction | null })}
        />
      </Group>

      <Divider />

      {rows.length === 0 ? (
        <Text c={color.textSecondary}>Nothing was logged for this view.</Text>
      ) : rows.length < LIST_LIMIT ? (
        <Stack gap={spacing.md}>
          {rows.map((row, index) => (
            <Stack key={row.id} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between" wrap="nowrap">
                <Stack gap={spacing.xs}>
                  <Text fw={fontWeight.semibold}>
                    {actionLabel(row.action)} in {tableLabel(row.table)}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {row.when}, {actorText(row)}
                  </Text>
                  {row.reason && (
                    <Text size="sm" c={color.textSecondary}>
                      {row.reason}
                    </Text>
                  )}
                </Stack>
                <Button variant="default" onClick={() => setOpen(row)}>
                  Details
                </Button>
              </Group>
            </Stack>
          ))}
        </Stack>
      ) : (
        <Table.ScrollContainer minWidth={840}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>When</Table.Th>
                <Table.Th>Who</Table.Th>
                <Table.Th>Action</Table.Th>
                <Table.Th>Table</Table.Th>
                <Table.Th>Reason</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((row) => (
                <Table.Tr key={row.id}>
                  <Table.Td>{row.when}</Table.Td>
                  <Table.Td>{actorText(row)}</Table.Td>
                  <Table.Td>{actionLabel(row.action)}</Table.Td>
                  <Table.Td>{tableLabel(row.table)}</Table.Td>
                  <Table.Td>{row.reason ?? ''}</Table.Td>
                  <Table.Td>
                    <Group justify="flex-end">
                      <Button variant="default" size="xs" onClick={() => setOpen(row)}>
                        Details
                      </Button>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {pages > 1 && (
        <Group justify="space-between">
          <Text size="sm" c={color.textSecondary}>
            {total} entries
          </Text>
          <Pagination total={pages} value={filters.page} onChange={(page) => go({ page })} />
        </Group>
      )}

      <Modal opened={open !== null} onClose={() => setOpen(null)} title="Log entry" centered size="lg">
        {open && <EntryDetails row={open} />}
      </Modal>
    </Stack>
  );
}

function EntryDetails({ row }: { row: AuditRow }) {
  const changes = changedFields(row.oldData, row.newData);
  return (
    <Stack gap={spacing.md}>
      <Stack gap={spacing.xs}>
        <Text fw={fontWeight.semibold}>
          {actionLabel(row.action)} in {tableLabel(row.table)}
        </Text>
        <Text size="sm" c={color.textSecondary}>
          {row.when}, {actorText(row)}
        </Text>
        {row.recordId && (
          <Text size="sm" c={color.textSecondary}>
            Record {row.recordId}
          </Text>
        )}
        {row.reason && <Text size="sm">Reason: {row.reason}</Text>}
      </Stack>

      <Divider />

      {changes.length === 0 ? (
        <Text c={color.textSecondary}>No field values were kept for this entry.</Text>
      ) : (
        <Table.ScrollContainer minWidth={480}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Field</Table.Th>
                <Table.Th>Before</Table.Th>
                <Table.Th>After</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {changes.map((change) => (
                <Table.Tr key={change.field}>
                  <Table.Td>{change.field}</Table.Td>
                  <Table.Td>{change.before}</Table.Td>
                  <Table.Td>{change.after}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Stack>
  );
}
