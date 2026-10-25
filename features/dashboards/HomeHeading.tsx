// The top of a role's home page: the page heading, a line of facts (today's
// date, the current term) and, only when something blocks the work, one
// warning with the link that fixes it.
import Link from 'next/link';
import { Anchor, Group, Stack, Text } from '@mantine/core';
import { ExclamationTriangleIcon } from '@heroicons/react/24/outline';
import { PageHeading } from '@/components/PageHeading';
import { color, layout, spacing } from '@/styles/tokens';

export type HomeWarning = { text: string; href?: string; linkLabel?: string };

export function HomeHeading({
  title,
  facts = [],
  warning,
}: {
  title: string;
  facts?: string[];
  warning?: HomeWarning;
}) {
  return (
    <Stack gap={spacing.xs}>
      <PageHeading title={title} />
      {facts.length > 0 && (
        <Group gap={spacing.md}>
          {facts.map((fact) => (
            <Text key={fact} size="sm" c={color.textSecondary}>
              {fact}
            </Text>
          ))}
        </Group>
      )}
      {warning && (
        <Group gap={spacing.sm} wrap="nowrap" align="flex-start" role="status">
          <ExclamationTriangleIcon width={layout.iconSize} height={layout.iconSize} color={color.warning} />
          <Text size="sm" c={color.warning}>
            {warning.text}{' '}
            {warning.href && warning.linkLabel && (
              <Anchor component={Link} href={warning.href} size="sm">
                {warning.linkLabel}
              </Anchor>
            )}
          </Text>
        </Group>
      )}
    </Stack>
  );
}
