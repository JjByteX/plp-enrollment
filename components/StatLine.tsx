// components/StatLine.tsx
//
// A few figures on one line, for the top of a working page: the number in
// bold, its label beside it, a thin divider between figures. Plain text, not
// cards, so it adds no weight to the page. It wraps on a narrow screen.
import { Divider, Group, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';

export type Stat = { value: string | number; label: string };

export function StatLine({ stats }: { stats: Stat[] }) {
  return (
    <Group gap={spacing.md} wrap="wrap" role="group" aria-label="Summary">
      {stats.map((stat, index) => (
        <Group key={stat.label} gap={spacing.md} wrap="nowrap">
          {index > 0 && <Divider orientation="vertical" h={16} />}
          <Text size="sm">
            <Text span fw={fontWeight.semibold}>
              {stat.value}
            </Text>{' '}
            <Text span c={color.textSecondary}>
              {stat.label}
            </Text>
          </Text>
        </Group>
      ))}
    </Group>
  );
}
