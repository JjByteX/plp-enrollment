// How full each section is, fullest first. A full section turns the bar to the
// warning color so the Secretary sees where a new section is needed; the
// numbers are always printed, the color is never the only signal.
import Link from 'next/link';
import { Anchor, Group, Progress, Stack, Text } from '@mantine/core';
import { color, fontWeight, layout, spacing } from '@/styles/tokens';
import type { SeatRow } from './queries';

export function SeatFill({ seats, href }: { seats: SeatRow[]; href?: string }) {
  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>Seats</Text>
      {seats.length === 0 ? (
        <Text c={color.textSecondary}>
          No section is set up yet.
          {href && (
            <>
              {' '}
              <Anchor component={Link} href={href} inherit>
                Add a section
              </Anchor>
            </>
          )}
        </Text>
      ) : (
        seats.map((seat) => (
          <Stack key={seat.id} gap={spacing.xs}>
            <Group justify="space-between" wrap="nowrap">
              <Text size="sm">{seat.label}</Text>
              <Text size="sm" c={seat.filled >= seat.capacity ? color.warning : color.textSecondary}>
                {seat.filled} of {seat.capacity}
              </Text>
            </Group>
            <Progress
              value={Math.min((seat.filled / seat.capacity) * 100, 100)}
              color={seat.filled >= seat.capacity ? color.warning : color.accent}
              size={layout.barHeight}
              aria-label={`${seat.label}: ${seat.filled} of ${seat.capacity} seats taken`}
            />
          </Stack>
        ))
      )}
    </Stack>
  );
}
