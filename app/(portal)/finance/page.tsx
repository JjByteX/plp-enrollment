import { Anchor, Stack, Title } from '@mantine/core';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Finance | PLP Enrollment' };

// Placeholder home. The real home screen arrives in build step 14.
export default function FinancePage() {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Finance</Title>
      <Anchor href="/finance/payments">Payments</Anchor>
    </Stack>
  );
}
