'use client';

import { useState, type FormEvent } from 'react';
import { Anchor, Button, PasswordInput, Stack, Text, TextInput } from '@mantine/core';
import { signIn } from '@/lib/auth/actions';
import { isEmail } from '@/lib/auth/validate';
import { color, spacing } from '@/styles/tokens';

export function LoginForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const ready = isEmail(email) && password.length > 0;

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!ready || loading) return;
    setLoading(true);
    setError(null);
    // signIn redirects on success, so a result only comes back as an error.
    const result = await signIn(email, password);
    if (result?.error) setError(result.error);
    setLoading(false);
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
        <PasswordInput
          label="Password"
          autoComplete="current-password"
          value={password}
          onChange={(event) => setPassword(event.currentTarget.value)}
          required
        />
        <Anchor href="/forgot-password" size="sm" ta="right">
          Forgot password?
        </Anchor>
        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}
        <Button type="submit" loading={loading} disabled={!ready}>
          Sign in
        </Button>
      </Stack>
    </form>
  );
}
