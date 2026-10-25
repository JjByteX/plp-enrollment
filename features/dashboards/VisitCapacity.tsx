// Visit seats over the coming days, against the applicants who still have no
// visit date. When the open seats cannot cover them, that is said first: it is
// the one thing here that needs the Registrar to act (add a slot).
import Link from 'next/link';
import { Anchor, Group, Progress, Stack, Text } from '@mantine/core';
import { ExclamationTriangleIcon } from '@heroicons/react/24/outline';
import { color, fontWeight, layout, spacing } from '@/styles/tokens';
import { plural, type VisitCapacityData } from './schema';

export function VisitCapacity({ data }: { data: VisitCapacityData }) {
  const short = data.unassigned > data.freeSeats;

  return (
    <Stack gap={spacing.md}>
      <Text fw={fontWeight.semibold}>Visit seats</Text>

      {short && (
        <Group gap={spacing.sm} wrap="nowrap" align="flex-start" role="status">
          <ExclamationTriangleIcon width={layout.iconSize} height={layout.iconSize} color={color.warning} />
          <Text size="sm" c={color.warning}>
            {data.unassigned} {plural(data.unassigned, 'applicant has', 'applicants have')} no visit date and{' '}
            {data.freeSeats} {plural(data.freeSeats, 'seat is', 'seats are')} open.{' '}
            <Anchor component={Link} href="/registrar/visits" size="sm">
              Add a slot
            </Anchor>
          </Text>
        </Group>
      )}

      {data.days.length === 0 ? (
        <Text c={color.textSecondary}>No open slot is coming up.</Text>
      ) : (
        data.days.map((day) => (
          <Stack key={day.date} gap={spacing.xs}>
            <Group justify="space-between">
              <Text size="sm">{day.label}</Text>
              <Text size="sm" c={color.textSecondary}>
                {day.booked} of {day.capacity}
              </Text>
            </Group>
            <Progress
              value={day.capacity === 0 ? 0 : (day.booked / day.capacity) * 100}
              color={color.accent}
              size={layout.barHeight}
              aria-label={`${day.label}: ${day.booked} of ${day.capacity} seats taken`}
            />
          </Stack>
        ))
      )}
    </Stack>
  );
}
