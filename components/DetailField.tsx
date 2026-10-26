// components/DetailField.tsx
//
// A small caption over a bold value, used by the slip and the COR (and any
// other read-only view that lists a few labelled facts). Shared so the same
// label-over-value block is not rewritten in each print view.
import { Stack, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';

export function DetailField({ label, value }: { label: string; value: string }) {
  return (
    <Stack gap={spacing.xs}>
      <Text size="sm" c={color.textSecondary}>
        {label}
      </Text>
      <Text fw={fontWeight.semibold}>{value}</Text>
    </Stack>
  );
}
