'use client';

// The create account form, in a centered modal. Admin picks a role (and a
// college for a Dean or College Secretary); the invitation email carries the
// set-password link. All of it goes through ./actions.
import { useState } from 'react';
import { Select, TextInput } from '@mantine/core';
import { FormModal, useFormAction } from '@/components/FormModal';
import { createStaffAccount, type CreateStaffResult } from './actions';
import { COLLEGE_ROLES, ROLE_LABEL, STAFF_ROLES } from '@/lib/auth/roles';
import { isEmail } from '@/lib/auth/validate';

const ROLE_OPTIONS = STAFF_ROLES.map((role) => ({ value: role, label: ROLE_LABEL[role] }));

export function AccountFormModal({
  colleges,
  onClose,
  onDone,
}: {
  colleges: { value: string; label: string }[];
  onClose: () => void;
  onDone: (email: string) => void;
}) {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<string | null>(null);
  const [collegeId, setCollegeId] = useState<string | null>(null);
  const { loading, error, run } = useFormAction<CreateStaffResult>((result) => {
    if ('ok' in result) onDone(result.email);
  });

  const needsCollege = role !== null && (COLLEGE_ROLES as readonly string[]).includes(role);

  let hint: string | null = null;
  if (fullName.trim().length < 2) hint = 'Enter the full name.';
  else if (!isEmail(email)) hint = 'Enter a valid email address.';
  else if (role === null) hint = 'Choose a role.';
  else if (needsCollege && collegeId === null) hint = 'Choose the college.';

  function onSubmit() {
    if (hint !== null || role === null) return;
    void run(() => createStaffAccount({ fullName, email, role, collegeId: needsCollege ? collegeId : null }));
  }

  return (
    <FormModal
      title="Create account"
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={hint}
      submitLabel="Create account"
      submitDisabled={hint !== null}
    >
      <TextInput label="Full name" value={fullName} onChange={(event) => setFullName(event.currentTarget.value)} required />
      <TextInput label="Email" type="email" value={email} onChange={(event) => setEmail(event.currentTarget.value)} required />
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
        <Select label="College" data={colleges} value={collegeId} onChange={setCollegeId} searchable required />
      )}
    </FormModal>
  );
}
