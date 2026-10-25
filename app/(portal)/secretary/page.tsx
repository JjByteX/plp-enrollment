import { Anchor, Stack, Title } from '@mantine/core';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'College Secretary | PLP Enrollment' };

// Placeholder. The real home screen arrives in build step 14.
export default function SecretaryPage() {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>College Secretary</Title>
      <Anchor href="/secretary/schedule">Schedules</Anchor>
    </Stack>
  );
}
