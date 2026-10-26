// Finance at a glance: what has been collected, who is next in line to be
// recorded, and the latest payments that cleared. Reference below the queue
// tile, so the order is action first, then the record of what was done.
import { Divider, Group, SimpleGrid, Stack, Text } from '@mantine/core';
import { color, fontFamily, fontSize, fontWeight, spacing } from '@/styles/tokens';
import { formatDate, formatPeso } from '@/lib/format';
import type { FinanceHome } from './queries';

function Figure({ value, caption }: { value: string; caption: string }) {
  return (
    <Stack gap={spacing.xs}>
      <Text fz={fontSize.display} fw={fontWeight.semibold} ff={fontFamily.heading} lh={1}>
        {value}
      </Text>
      <Text size="sm" c={color.textSecondary}>
        {caption}
      </Text>
    </Stack>
  );
}

export function FinanceSummary({ home }: { home: FinanceHome }) {
  return (
    <Stack gap={spacing.lg}>
      <Group gap={spacing['3xl']} align="flex-end">
        <Figure value={formatPeso(home.collected)} caption="collected" />
        <Figure value={String(home.clearedCount)} caption="cleared" />
      </Group>

      <Divider />

      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing={spacing.xl}>
        <Stack gap={spacing.md}>
          <Text fw={fontWeight.semibold}>Next in line</Text>
          {home.pending.length === 0 ? (
            <Text c={color.textSecondary}>No payment is waiting.</Text>
          ) : (
            home.pending.map((row, index) => (
              <Stack key={row.studentId} gap={spacing.sm}>
                {index > 0 && <Divider />}
                <Stack gap={spacing.xs}>
                  <Text>
                    {row.studentNumber}, {row.fullName}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {row.section}
                  </Text>
                </Stack>
              </Stack>
            ))
          )}
        </Stack>

        <Stack gap={spacing.md}>
          <Text fw={fontWeight.semibold}>Recently cleared</Text>
          {home.recent.length === 0 ? (
            <Text c={color.textSecondary}>No payment has been recorded yet.</Text>
          ) : (
            home.recent.map((row, index) => (
              <Stack key={row.studentId} gap={spacing.sm}>
                {index > 0 && <Divider />}
                <Stack gap={spacing.xs}>
                  <Text>
                    {row.studentNumber}, {row.fullName}
                  </Text>
                  <Text size="sm" c={color.textSecondary}>
                    {formatPeso(row.amountPaid)}
                    {row.receiptNo ? `, receipt ${row.receiptNo}` : ''}
                    {row.clearedAt ? `, ${formatDate(row.clearedAt)}` : ''}
                  </Text>
                </Stack>
              </Stack>
            ))
          )}
        </Stack>
      </SimpleGrid>
    </Stack>
  );
}
