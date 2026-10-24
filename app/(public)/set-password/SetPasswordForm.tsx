'use client';

import { useState, type FormEvent } from 'react';
import { Button, PasswordInput, Stack, Text } from '@mantine/core';
import { setPassword } from '@/lib/auth/actions';
import { MIN_PASSWORD_LENGTH, checkPassword } from '@/lib/auth/validate';
import { color, spacing } from '@/styles/tokens';

export function SetPasswordForm() {
  const [password, setPasswordValue] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const problem = checkPassword(password, confirm);
  // Say what is missing only once the person has typed in the second field.
  const hint = confirm.length > 0 ? problem : null;

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (problem || loading) return;
    setLoading(true);
    setError(null);
    // setPassword redirects on success, so a result only comes back as an error.
    const result = await setPassword(password, confirm);
    if (result?.error) setError(result.error);
    setLoading(false);
  }

  return (
    <form onSubmit={onSubmit}>
      <Stack gap={spacing.md}>
        <PasswordInput
          label="New password"
          description={`At least ${MIN_PASSWORD_LENGTH} characters`}
          autoComplete="new-password"
          value={password}
          onChange={(event) => setPasswordValue(event.currentTarget.value)}
          required
        />
        <PasswordInput
          label="Confirm password"
          autoComplete="new-password"
          value={confirm}
          onChange={(event) => setConfirm(event.currentTarget.value)}
          error={hint}
          required
        />
        {error && (
          <Text size="sm" c={color.error} role="alert">
            {error}
          </Text>
        )}
        <Button type="submit" loading={loading} disabled={problem !== null}>
          Set password
        </Button>
      </Stack>
    </form>
  );
}
