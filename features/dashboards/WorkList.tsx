// The staff home queue. What waits on the person comes first, as one large
// tile per page with its count: each tile is its own destination with its own
// state, so a tile is the right container here (ux-ui-guidelines.md, card
// restraint). Pages with nothing waiting, or nothing to count, follow as
// plain shortcuts. The tile icon is the one the sidebar uses for that page.
import Link from 'next/link';
import { Anchor, Group, Paper, SimpleGrid, Stack, Text } from '@mantine/core';
import { ArrowRightIcon, CheckCircleIcon } from '@heroicons/react/24/solid';
import { NAV_ICONS } from '@/components/NavIcons';
import { color, fontFamily, fontSize, fontWeight, layout, padding, spacing } from '@/styles/tokens';
import { nothingWaiting, type WorkItem } from './schema';

function Tile({ item }: { item: WorkItem }) {
  const Icon = NAV_ICONS[item.icon];
  return (
    <Paper component={Link} href={item.href} className="plp-tile" p={padding.card}>
      <Stack gap={spacing.md}>
        <Group justify="space-between" wrap="nowrap">
          <Group gap={spacing.sm} wrap="nowrap">
            <Icon width={layout.iconSize} height={layout.iconSize} color={color.textSecondary} />
            <Text fw={fontWeight.semibold}>{item.label}</Text>
          </Group>
          <ArrowRightIcon width={layout.iconSize} height={layout.iconSize} color={color.accent} />
        </Group>
        <Group align="baseline" gap={spacing.sm} wrap="nowrap">
          <Text fz={fontSize.display} fw={fontWeight.semibold} ff={fontFamily.heading} lh={1}>
            {item.waiting}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            waiting
          </Text>
        </Group>
      </Stack>
    </Paper>
  );
}

export function WorkList({ items }: { items: WorkItem[] }) {
  const waiting = items.filter((item) => item.waiting !== null && item.waiting > 0);
  // One shortcut per page: two counts can lead to the same page (Schedules).
  const shortcuts = items.filter(
    (item, index) =>
      (item.waiting === null || item.waiting === 0) && items.findIndex((other) => other.href === item.href) === index
  );

  return (
    <Stack gap={spacing.lg}>
      {waiting.length > 0 && (
        <Stack gap={spacing.md}>
          <Text fw={fontWeight.semibold}>Needs action</Text>
          <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing={spacing.md}>
            {waiting.map((item) => (
              <Tile key={`${item.href}-${item.label}`} item={item} />
            ))}
          </SimpleGrid>
        </Stack>
      )}

      {nothingWaiting(items) && (
        <Group gap={spacing.sm} wrap="nowrap">
          <CheckCircleIcon width={layout.iconSize} height={layout.iconSize} color={color.success} />
          <Text>Nothing is waiting.</Text>
        </Group>
      )}

      {shortcuts.length > 0 && (
        <Stack gap={spacing.md}>
          <Text fw={fontWeight.semibold}>Shortcuts</Text>
          <Group gap={spacing.lg}>
            {shortcuts.map((item) => {
              const Icon = NAV_ICONS[item.icon];
              return (
                <Group key={`${item.href}-${item.label}`} gap={spacing.sm} wrap="nowrap">
                  <Icon width={layout.iconSize} height={layout.iconSize} color={color.textSecondary} />
                  <Anchor component={Link} href={item.href}>
                    {item.label}
                  </Anchor>
                </Group>
              );
            })}
          </Group>
        </Stack>
      )}
    </Stack>
  );
}
