// The newest changes in the audit log, for Admin: what changed, who did it and
// when. The full log, with filters and field changes, is one link away.
import Link from 'next/link';
import { Anchor, Divider, Group, Stack, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { ActivityItem } from './schema';

export function RecentActivity({ items }: { items: ActivityItem[] }) {
  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between">
        <Text fw={fontWeight.semibold}>Recent changes</Text>
        <Anchor component={Link} href="/admin/audit" size="sm">
          View all
        </Anchor>
      </Group>
      {items.length === 0 ? (
        <Text c={color.textSecondary}>Nothing was logged yet.</Text>
      ) : (
        items.map((item, index) => (
          <Stack key={item.id} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Stack gap={spacing.xs}>
              <Text>{item.text}</Text>
              <Text size="sm" c={color.textSecondary}>
                {item.when}, {item.actor}
              </Text>
            </Stack>
          </Stack>
        ))
      )}
    </Stack>
  );
}
