'use client';

// features/withdraw-enrollment/WithdrawMyEnrollmentModal.tsx
//
// "Withdraw enrollment" from the profile menu, for an Applicant or Student who
// has not been issued a COR yet (after that the Registrar records it). The shell
// owns whether the modal is open. The person types the word withdraw to confirm.
import { WithdrawModal } from './WithdrawModal';
import { withdrawMyEnrollment } from './actions';
import { CONFIRM_WORD } from './schema';

export function WithdrawMyEnrollmentModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  return (
    <WithdrawModal
      opened={opened}
      onClose={onClose}
      description="You will lose your visit date and your seat in your section, and your enrollment will be closed. You cannot undo this yourself: to come back, you contact the Registrar."
      confirmText={CONFIRM_WORD}
      onConfirm={withdrawMyEnrollment}
    />
  );
}
