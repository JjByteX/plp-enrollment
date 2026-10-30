// components/PrintSheets.tsx
//
// The page body of the Registrar's print views: any number of documents, one
// per printed page, with a Back link and one print button above that are
// hidden on paper. Used by /print/cor and /print/slip.
import type { ReactNode } from 'react';
import { Anchor, Container, Group, Stack, Text } from '@mantine/core';
import { PrintButton } from '@/features/assessment-slip/PrintButton';
import { color, spacing } from '@/styles/tokens';

export function PrintSheets({
  backHref,
  summary,
  emptyText,
  sheets,
}: {
  backHref: string;
  summary: string; // e.g. "3 certificates of registration"
  emptyText: string;
  sheets: ReactNode[];
}) {
  return (
    <Container size="md" py={spacing.xl}>
      <style>{'@media print { .print-sheet { break-after: page; } .print-sheet:last-child { break-after: auto; } }'}</style>
      <Stack gap={spacing.md}>
        <Group justify="space-between" className="no-print">
          <Anchor href={backHref}>Back</Anchor>
          {sheets.length > 0 && (
            <Group gap={spacing.md}>
              <Text size="sm" c={color.textSecondary}>
                {summary}
              </Text>
              <PrintButton />
            </Group>
          )}
        </Group>
        {sheets.length === 0 ? (
          <Text c={color.textSecondary}>{emptyText}</Text>
        ) : (
          sheets.map((sheet, index) => (
            <div key={index} className="print-sheet">
              {sheet}
            </div>
          ))
        )}
      </Stack>
    </Container>
  );
}
