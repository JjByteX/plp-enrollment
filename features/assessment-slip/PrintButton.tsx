'use client';

// "Print or save as PDF": opens the browser's print dialog, which can save the
// slip as a PDF. The button and the back link are hidden on the printed page.
import { Button } from '@mantine/core';

export function PrintButton() {
  return (
    <>
      <style>{'@media print { .no-print { display: none !important; } }'}</style>
      <Button className="no-print" onClick={() => window.print()}>
        Print or save as PDF
      </Button>
    </>
  );
}
