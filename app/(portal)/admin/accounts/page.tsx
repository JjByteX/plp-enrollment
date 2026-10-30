import { Stack, Title } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { createClient } from '@/lib/supabase/server';
import { spacing } from '@/styles/tokens';
import { AccountForm } from './AccountForm';
import { AccountsList, type AccountRow } from './AccountsList';

export const metadata = { title: 'Accounts | PLP Enrollment' };

type RawAccount = {
  id: string;
  full_name: string;
  email: string;
  role: string;
  college_id: string | null;
  is_active: boolean;
  created_at: string;
};

// Admin only: the admin layout checks the role, and row level security on
// users lets Admin read every account.
export default async function AccountsPage() {
  const supabase = createClient();
  const [collegesResult, usersResult] = await Promise.all([
    supabase.from('colleges').select('id, name').order('name'),
    supabase
      .from('users')
      .select('id, full_name, email, role, college_id, is_active, created_at')
      .order('created_at', { ascending: false }),
  ]);

  const collegeRows = (collegesResult.data ?? []) as { id: string; name: string }[];
  const colleges = collegeRows.map((college) => ({ value: college.id, label: college.name }));
  const collegeName = new Map(collegeRows.map((college) => [college.id, college.name]));

  const accounts: AccountRow[] = ((usersResult.data ?? []) as RawAccount[]).map((user) => ({
    id: user.id,
    fullName: user.full_name,
    email: user.email,
    role: user.role,
    college: user.college_id ? collegeName.get(user.college_id) ?? null : null,
    isActive: user.is_active,
    createdAt: user.created_at,
  }));

  return (
    <Stack gap={spacing.md}>
      <PageHeading title="Accounts" parent={{ label: 'Admin', href: '/admin' }} />
      <AccountForm colleges={colleges} />
      <Title order={3} size="h4">
        All accounts ({accounts.length})
      </Title>
      <AccountsList rows={accounts} />
    </Stack>
  );
}
