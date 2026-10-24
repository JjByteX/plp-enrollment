import { Anchor, Stack, Title } from '@mantine/core';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Registrar | PLP Enrollment' };

// Placeholder home. The real home screen arrives in build step 14.
export default function RegistrarPage() {
  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Registrar</Title>
      <Anchor href="/registrar/visits">Visits</Anchor>
    </Stack>
  );
}
