// The sections that wait on the Dean (to sign off) or the Secretary (drafts to
// finish), with how complete each one is. Each row opens the schedules page on
// the matching status filter.
import Link from 'next/link';
import { Anchor, Divider, Group, Stack, Text } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import type { SectionAttention } from './schema';

export function SectionsAttention({
  title,
  empty,
  href,
  sections,
  total,
}: {
  title: string;
  empty: string;
  href: string;
  sections: SectionAttention[];
  total: number;
}) {
  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>{title}</Text>
      {sections.length === 0 ? (
        <Text c={color.textSecondary}>{empty}</Text>
      ) : (
        <>
          {sections.map((section, index) => (
            <Stack key={section.id} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group justify="space-between" wrap="nowrap" align="flex-start">
                <Stack gap={spacing.xs}>
                  <Text>{section.label}</Text>
                  <Text size="sm" c={color.textSecondary}>
                    {section.detail}
                  </Text>
                </Stack>
                <Anchor component={Link} href={href} size="sm">
                  Open
                </Anchor>
              </Group>
            </Stack>
          ))}
          {total > sections.length && (
            <Text size="sm" c={color.textSecondary}>
              and {total - sections.length} more
            </Text>
          )}
        </>
      )}
    </Stack>
  );
}
