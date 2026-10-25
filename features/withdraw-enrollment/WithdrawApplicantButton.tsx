'use client';

// features/withdraw-enrollment/WithdrawApplicantButton.tsx
//
// The Registrar's "Withdraw" button on a row of the Documents lists (step 17):
// an applicant who never came, or a student who left, including one who already
// has a COR (the COR stays on record). The Registrar types the person's student
// number, or their applicant reference before they are a student, so the wrong
// row is caught. The person is told, with the reason.
import { useState } from 'react';
import { Button } from '@mantine/core';
import { color } from '@/styles/tokens';
import { WithdrawModal } from './WithdrawModal';
import { withdrawApplicant } from './actions';

export function WithdrawApplicantButton({
  applicantId,
  name,
  identifier,
}: {
  applicantId: string;
  name: string;
  identifier: string; // student number, or applicant reference before they are a student
}) {
  const [opened, setOpened] = useState(false);

  return (
    <>
      <Button variant="subtle" color={color.error} size="xs" onClick={() => setOpened(true)}>
        Withdraw
      </Button>
      <WithdrawModal
        opened={opened}
        onClose={() => setOpened(false)}
        description={`${name} (${identifier}) will lose their visit date and their seat, and will be told why. Any COR already issued stays on record. This cannot be undone here.`}
        confirmText={identifier}
        onConfirm={(reason) => withdrawApplicant({ applicantId, reason })}
      />
    </>
  );
}
