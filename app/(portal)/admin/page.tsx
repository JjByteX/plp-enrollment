import { Anchor, Stack, Title } from '@mantine/core';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Admin | PLP Enrollment' };

// Placeholder home. The real home screen arrives in build step 14.
export default function AdminPage() {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Admin</Title>
      <Anchor href="/admin/accounts">Accounts</Anchor>
      <Anchor href="/admin/admissions">Admissions</Anchor>
      <Anchor href="/registrar/visits">Visits</Anchor>
      <Anchor href="/registrar/documents">Documents</Anchor>
      <Anchor href="/registrar/schedules">Schedules</Anchor>
      <Anchor href="/registrar/slips">Slips</Anchor>
      <Anchor href="/finance/payments">Payments</Anchor>
      <Anchor href="/registrar/cors">COR</Anchor>
    </Stack>
  );
}
