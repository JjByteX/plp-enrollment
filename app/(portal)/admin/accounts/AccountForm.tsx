'use client';

import { useState, type FormEvent } from 'react';
import { Button, Paper, Select, Stack, Text, TextInput } from '@mantine/core';
import { createStaffAccount } from './actions';
import { COLLEGE_ROLES, ROLE_LABEL, STAFF_ROLES } from '@/lib/auth/roles';
import { isEmail } from '@/lib/auth/validate';
import { color, padding, spacing } from '@/styles/tokens';

const ROLE_OPTIONS = STAFF_ROLES.map((role) => ({ value: role, label: ROLE_LABEL[role] }));

export function AccountForm({ colleges }: { colleges: { value: string; label: string }[] }) {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<string | null>(null);
  const [collegeId, setCollegeId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const needsCollege = role !== null && (COLLEGE_ROLES as readonly string[]).includes(role);
  const ready = fullName.trim().length >= 2 && isEmail(email) && role !== null && (!needsCollege || collegeId !== null);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!ready || loading || role === null) return;
    setLoading(true);
    setError(null);
    setSentTo(null);
    const result = await createStaffAccount({ fullName, email, role, collegeId: needsCollege ? collegeId : null });
    if ('error' in result) {
      setError(result.error);
    } else {
      setSentTo(result.email);
      setFullName('');
      setEmail('');
      setRole(null);
      setCollegeId(null);
    }
    setLoading(false);
  }

  return (
    <Paper p={padding.card} maw={480}>
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <TextInput label="Full name" value={fullName} onChange={(event) => setFullName(event.currentTarget.value)} required />
          <TextInput
            label="Email"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.currentTarget.value)}
            required
          />
          <Select
            label="Role"
            data={ROLE_OPTIONS}
            value={role}
            onChange={(value) => {
              setRole(value);
              setCollegeId(null);
            }}
            required
          />
          {needsCollege && (
            <Select
              label="College"
              data={colleges}
              value={collegeId}
              onChange={setCollegeId}
              searchable
              required
            />
          )}
          {error && (
            <Text size="sm" c={color.error} role="alert">
              {error}
            </Text>
          )}
          {sentTo && (
            <Text size="sm" c={color.success} role="status">
              Invitation sent to {sentTo}.
            </Text>
          )}
          <Button type="submit" loading={loading} disabled={!ready}>
            Create account
          </Button>
        </Stack>
      </form>
    </Paper>
  );
}
