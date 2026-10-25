// The staff home list: every page of the role, with what waits on it. Pages
// with something waiting come first (ux-ui-guidelines.md, dashboard rules:
// what needs action first). One container divided by lines, no cards. The
// waiting count is a pill: text only, neutral text, tinted background.
import { Anchor, Divider, Group, Stack, Text } from '@mantine/core';
import { color, padding, radius, spacing } from '@/styles/tokens';
import { byImportance, nothingWaiting, waitingLabel, type WorkItem } from './schema';

export function WorkList({ items }: { items: WorkItem[] }) {
  const sorted = byImportance(items);

  return (
    <Stack gap={spacing.md}>
      {sorted.map((item, index) => (
        <Stack key={item.href} gap={spacing.md}>
          {index > 0 && <Divider />}
          <Group justify="space-between" wrap="nowrap">
            <Anchor href={item.href}>{item.label}</Anchor>
            {item.waiting !== null && item.waiting > 0 && (
              <Text
                size="sm"
                c={color.textPrimary}
                style={{ background: color.accentSubtleBg, padding: padding.control, borderRadius: radius.default }}
              >
                {waitingLabel(item.waiting)}
              </Text>
            )}
          </Group>
        </Stack>
      ))}
      {nothingWaiting(items) && (
        <Text size="sm" c={color.textSecondary}>
          Nothing is waiting.
        </Text>
      )}
    </Stack>
  );
}
