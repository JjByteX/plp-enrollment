'use client';

// features/correct-student-details/CorrectDetailsButton.tsx
//
// The "Correct" button on a row of the Documents page, Received tab. It opens
// the correction window for that student.
import { useState } from 'react';
import { Button } from '@mantine/core';
import { CorrectDetailsModal } from './CorrectDetailsModal';

export function CorrectDetailsButton({
  applicantId,
  studentNumber,
  fullName,
  email,
}: {
  applicantId: string;
  studentNumber: string;
  fullName: string;
  email: string;
}) {
  const [opened, setOpened] = useState(false);

  return (
    <>
      <Button variant="default" size="xs" onClick={() => setOpened(true)}>
        Correct
      </Button>
      {opened && (
        <CorrectDetailsModal
          applicantId={applicantId}
          studentNumber={studentNumber}
          fullName={fullName}
          email={email}
          onClose={() => setOpened(false)}
        />
      )}
    </>
  );
}
