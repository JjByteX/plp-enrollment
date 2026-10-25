import { Anchor, Stack, Title } from '@mantine/core';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Dean | PLP Enrollment' };

// Placeholder. The real home screen arrives in build step 14.
export default function DeanPage() {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Dean</Title>
      <Anchor href="/secretary/schedule">Schedules</Anchor>
    </Stack>
  );
}
