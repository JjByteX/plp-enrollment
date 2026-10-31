'use client';

import { useState, type FormEvent } from 'react';
import { Anchor, Button, Stack, Text, TextInput } from '@mantine/core';
import { requestPasswordReset } from '@/lib/auth/actions';
import { isEmail } from '@/lib/auth/validate';
import { color, spacing } from '@/styles/tokens';

export function ForgotPasswordForm() {
  const [email, setEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!isEmail(email) || loading) return;
    setLoading(true);
    setError(null);
    const result = await requestPasswordReset(email);
    if ('error' in result) setError(result.error);
    else setSent(true);
    setLoading(false);
  }

  if (sent) {
    return (
      <Stack gap={spacing.sm}>
        <Text>
          If an account exists for <strong>{email.trim()}</strong>, a reset link is on its way. Check your inbox and
          spam folder. The link works once and expires after a while.
        </Text>
        <Anchor href="/login">Back to sign in</Anchor>
      </Stack>
    );
  }

  return (
    <form onSubmit={onSubmit}>
      <Stack gap={spacing.md}>
        <TextInput
          label="Email"
          type="email"
          autoComplete="username"
          value={email}
          onChange={(event) => setEmail(event.currentTarget.value)}
          required
        />
        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}
        <Button type="submit" loading={loading} disabled={!isEmail(email)}>
          Send reset link
        </Button>
        <Anchor href="/login" size="sm" ta="center">
          Back to sign in
        </Anchor>
      </Stack>
    </form>
  );
}
