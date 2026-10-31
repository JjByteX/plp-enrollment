import { Anchor, Container, Paper, Stack, Text, Title } from '@mantine/core';
import { getCurrentUser } from '@/lib/auth/session';
import { padding, spacing } from '@/styles/tokens';
import { SetPasswordForm } from './SetPasswordForm';

export const metadata = { title: 'Set password | PLP Enrollment' };

// People arrive here from the emailed link. /auth/confirm checks the link and
// signs them in first, so no session means the link is expired or already used.
export default async function SetPasswordPage() {
  const user = await getCurrentUser();

  return (
    <Container size="xs" py={spacing['4xl']}>
      <Paper p={padding.card}>
        <Stack gap={spacing.md}>
          <Title order={2}>Set password</Title>
          {user ? (
            <SetPasswordForm />
          ) : (
            <Stack gap={spacing.sm}>
              <Text>This link has expired or was already used.</Text>
              <Anchor href="/forgot-password">Send me a new link</Anchor>
              <Anchor href="/login">Back to sign in</Anchor>
            </Stack>
          )}
        </Stack>
      </Paper>
    </Container>
  );
}
