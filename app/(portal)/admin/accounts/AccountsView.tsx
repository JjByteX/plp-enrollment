'use client';

// The Accounts page body: the heading with a Create account button at the top
// right, the filters, the success line, and the list of accounts. The list
// opens on staff only, because applicants and students are many and are not
// created here; the Role filter can show them too. Creating opens a centered
// modal; when it succeeds the list is read again.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Group, Select, Stack, Text, TextInput, Title } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { FormMessage, type FormMessageValue } from '@/components/FormMessage';
import { ROLES, ROLE_LABEL } from '@/lib/auth/roles';
import { color, spacing } from '@/styles/tokens';
import { AccountFormModal } from './AccountForm';
import { AccountsList, type AccountRow } from './AccountsList';

const NOT_STAFF = ['applicant', 'student'];

const ROLE_FILTER = [
  { value: 'staff', label: 'Staff' },
  { value: 'all', label: 'Everyone' },
  ...ROLES.map((role) => ({ value: role, label: ROLE_LABEL[role] })),
];

const STATUS_FILTER = [
  { value: 'all', label: 'Any status' },
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
];

export function AccountsView({
  colleges,
  accounts,
}: {
  colleges: { value: string; label: string }[];
  accounts: AccountRow[];
}) {
  const router = useRouter();
  const [creating, setCreating] = useState(false);
  const [message, setMessage] = useState<FormMessageValue | null>(null);
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('staff');
  const [college, setCollege] = useState<string | null>(null);
  const [status, setStatus] = useState('all');

  const needle = search.trim().toLowerCase();
  const shown = accounts.filter((account) => {
    if (role === 'staff' ? NOT_STAFF.includes(account.role) : role !== 'all' && account.role !== role) return false;
    if (college && account.college !== college) return false;
    if (status === 'active' && !account.isActive) return false;
    if (status === 'inactive' && account.isActive) return false;
    if (needle && !account.fullName.toLowerCase().includes(needle) && !account.email.toLowerCase().includes(needle)) {
      return false;
    }
    return true;
  });

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between" wrap="wrap">
        <PageHeading title="Accounts" parent={{ label: 'Admin', href: '/admin' }} />
        <Button
          onClick={() => {
            setMessage(null);
            setCreating(true);
          }}
        >
          Create account
        </Button>
      </Group>

      <FormMessage message={message} />

      <Group gap={spacing.sm} align="flex-end" wrap="wrap">
        <TextInput
          label="Search"
          placeholder="Name or email"
          value={search}
          onChange={(event) => setSearch(event.currentTarget.value)}
          w={240}
        />
        <Select label="Role" data={ROLE_FILTER} value={role} onChange={(value) => setRole(value ?? 'staff')} allowDeselect={false} w={180} />
        <Select
          label="College"
          placeholder="All colleges"
          data={colleges.map((item) => item.label)}
          value={college}
          onChange={setCollege}
          clearable
          searchable
          w={240}
        />
        <Select label="Status" data={STATUS_FILTER} value={status} onChange={(value) => setStatus(value ?? 'all')} allowDeselect={false} w={150} />
      </Group>

      <Title order={3} size="h4">
        Accounts ({shown.length} of {accounts.length})
      </Title>
      {shown.length === 0 ? (
        <Text c={color.textSecondary}>{accounts.length === 0 ? 'No accounts yet.' : 'No account matches these filters.'}</Text>
      ) : (
        <AccountsList rows={shown} />
      )}

      {creating && (
        <AccountFormModal
          colleges={colleges}
          onClose={() => setCreating(false)}
          onDone={(email) => {
            setCreating(false);
            setMessage({ message: `Invitation sent to ${email}.` });
            router.refresh();
          }}
        />
      )}
    </Stack>
  );
}
