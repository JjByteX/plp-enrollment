import { redirect } from 'next/navigation';
import { Container, Paper, Stack, Text, Title } from '@mantine/core';
import { getCurrentUser } from '@/lib/auth/session';
import { homePath } from '@/lib/auth/roles';
import { padding, spacing } from '@/styles/tokens';
import { LoginForm } from './LoginForm';

export const metadata = { title: 'Sign in | PLP Enrollment' };

export default async function LoginPage() {
  const user = await getCurrentUser();
  if (user) redirect(homePath(user.role));

  return (
    <Container size="xs" py={spacing['4xl']}>
      <Paper p={padding.card}>
        <Stack gap={spacing.md}>
          <Stack gap={spacing.xs}>
            <Title order={2}>Sign in</Title>
            <Text c="dimmed" size="sm">
              PLP Enrollment
            </Text>
          </Stack>
          <LoginForm />
        </Stack>
      </Paper>
    </Container>
  );
}
