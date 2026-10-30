'use client';

// The Admin accounts list: every staff and student account, newest first.
// Fewer than 5 rows render as a list, 5 or more as a table (ux-ui-guidelines.md).
import { Badge, Group, Stack, Text } from '@mantine/core';
import { ListOrTable } from '@/components/ListOrTable';
import { ROLE_LABEL, isRole } from '@/lib/auth/roles';
import { formatDate } from '@/lib/format';
import { color, fontWeight } from '@/styles/tokens';

export type AccountRow = {
  id: string;
  fullName: string;
  email: string;
  role: string;
  college: string | null;
  isActive: boolean;
  createdAt: string;
};

function roleLabel(role: string): string {
  return isRole(role) ? ROLE_LABEL[role] : role;
}

function StatusBadge({ active }: { active: boolean }) {
  return (
    <Badge variant="light" color={active ? 'green' : 'gray'}>
      {active ? 'Active' : 'Inactive'}
    </Badge>
  );
}

export function AccountsList({ rows }: { rows: AccountRow[] }) {
  if (rows.length === 0) {
    return (
      <Text size="sm" c={color.textSecondary}>
        No accounts yet.
      </Text>
    );
  }

  return (
    <ListOrTable
      rows={rows}
      rowKey={(row) => row.id}
      minWidth={720}
      item={(row) => (
        <Stack gap={2}>
          <Group justify="space-between" wrap="nowrap">
            <Text fw={fontWeight.semibold}>{row.fullName}</Text>
            <StatusBadge active={row.isActive} />
          </Group>
          <Text size="sm" c={color.textSecondary}>
            {row.email}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {roleLabel(row.role)}
            {row.college ? ` · ${row.college}` : ''} · Added {formatDate(row.createdAt)}
          </Text>
        </Stack>
      )}
      columns={[
        { header: 'Name', cell: (row) => row.fullName },
        { header: 'Email', cell: (row) => row.email },
        { header: 'Role', cell: (row) => roleLabel(row.role) },
        { header: 'College', cell: (row) => row.college ?? '—' },
        { header: 'Status', cell: (row) => <StatusBadge active={row.isActive} /> },
        { header: 'Added', cell: (row) => formatDate(row.createdAt) },
      ]}
    />
  );
}
