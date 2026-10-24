import { Stack, Title } from '@mantine/core';
import { createClient } from '@/lib/supabase/server';
import { spacing } from '@/styles/tokens';
import { AccountForm } from './AccountForm';

export const metadata = { title: 'Accounts | PLP Enrollment' };

export default async function AccountsPage() {
  const supabase = createClient();
  const { data } = await supabase.from('colleges').select('id, name').order('name');
  const colleges = ((data ?? []) as { id: string; name: string }[]).map((college) => ({
    value: college.id,
    label: college.name,
  }));

  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Accounts</Title>
      <AccountForm colleges={colleges} />
    </Stack>
  );
}
