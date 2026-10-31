import { redirect } from 'next/navigation';
import { Container, Paper, Stack, Text, Title } from '@mantine/core';
import { getCurrentUser } from '@/lib/auth/session';
import { homePath } from '@/lib/auth/roles';
import { padding, spacing } from '@/styles/tokens';
import { ForgotPasswordForm } from './ForgotPasswordForm';

export const metadata = { title: 'Forgot password | PLP Enrollment' };

export default async function ForgotPasswordPage() {
  const user = await getCurrentUser();
  if (user) redirect(homePath(user.role));

  return (
    <Container size="xs" py={spacing['4xl']}>
      <Paper p={padding.card}>
        <Stack gap={spacing.md}>
          <Stack gap={spacing.xs}>
            <Title order={2}>Forgot password</Title>
            <Text c="dimmed" size="sm">
              Enter the email on your account and we will send you a link to choose a new password.
            </Text>
          </Stack>
          <ForgotPasswordForm />
        </Stack>
      </Paper>
    </Container>
  );
}
