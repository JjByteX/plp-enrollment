'use client';

// The Registrar's reschedules page body: the requests waiting for an answer,
// and the mass reschedule. Fewer than 5 requests render as a list, 5 or more
// as a table (ux-ui-guidelines.md). Answering opens a centered modal. All
// changes go through the feature actions.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Stack, Table, Tabs, Text, Title } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { MassReschedulePanel } from '@/features/reschedule-mass/MassReschedulePanel';
import type { BookedVisit } from '@/features/reschedule-mass/queries';
import type { SlotRow } from '@/features/visit-scheduling/queries';
import type { RescheduleActionResult } from './actions';
import { DecideRescheduleModal } from './DecideRescheduleModal';
import type { PendingRequest } from './queries';
import { formatRequestedDate, formatSlotDate, windowLabel } from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

export type ReschedulesTab = 'requests' | 'mass';

export function ReschedulesAdmin({
  tab,
  requests,
  openSlots,
  date,
  today,
  booked,
}: {
  tab: ReschedulesTab;
  requests: PendingRequest[];
  openSlots: SlotRow[]; // open slots with a free seat for the programs of the requests
  date: string | null;
  today: string;
  booked: BookedVisit[]; // visits still booked on the chosen date (mass tab)
}) {
  const router = useRouter();
  const [message, setMessage] = useState<RescheduleActionResult | null>(null);
  const [answering, setAnswering] = useState<PendingRequest | null>(null);

  function setTab(next: string | null) {
    setMessage(null);
    router.replace(next === 'mass' ? '/registrar/reschedules?tab=mass' : '/registrar/reschedules');
  }

  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Reschedules</Title>

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="requests">Requests</Tabs.Tab>
          <Tabs.Tab value="mass">Mass reschedule</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      {message && (
        <Text size="sm" c={'error' in message ? color.error : color.success} role="status">
          {'error' in message ? message.error : message.message}
        </Text>
      )}

      <Divider />

      {tab === 'requests' && <RequestRows requests={requests} onOpen={setAnswering} />}
      {tab === 'mass' && <MassReschedulePanel date={date} today={today} booked={booked} onResult={setMessage} />}

      {answering && (
        <DecideRescheduleModal
          request={answering}
          slots={openSlots.filter((slot) => slot.programId === answering.programId && slot.id !== answering.currentSlotId)}
          onClose={() => setAnswering(null)}
          onDone={(result) => {
            setAnswering(null);
            setMessage(result);
          }}
        />
      )}
    </Stack>
  );
}

function visitText(request: PendingRequest): string {
  return `${formatSlotDate(request.slotDate)}, ${windowLabel(request.startTime, request.endTime)}, ${request.officeName}`;
}

function RequestRows({ requests, onOpen }: { requests: PendingRequest[]; onOpen: (request: PendingRequest) => void }) {
  if (requests.length === 0) return <Text c={color.textSecondary}>No request is waiting.</Text>;

  if (requests.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {requests.map((request, index) => (
          <Stack key={request.requestId} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap" align="flex-start">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {request.fullName} ({request.applicantRef})
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {request.programCode}, {visitText(request)}
                </Text>
                <Text size="sm" lineClamp={2}>
                  {request.reason}
                </Text>
              </Stack>
              <Button variant="default" onClick={() => onOpen(request)}>
                Review
              </Button>
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={900}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Applicant</Table.Th>
            <Table.Th>Program</Table.Th>
            <Table.Th>Visit</Table.Th>
            <Table.Th>Reason</Table.Th>
            <Table.Th>Sent</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {requests.map((request) => (
            <Table.Tr key={request.requestId}>
              <Table.Td>
                {request.fullName} ({request.applicantRef})
              </Table.Td>
              <Table.Td>{request.programCode}</Table.Td>
              <Table.Td>{visitText(request)}</Table.Td>
              <Table.Td>
                <Text size="sm" lineClamp={2}>
                  {request.reason}
                </Text>
              </Table.Td>
              <Table.Td>{formatRequestedDate(request.requestedAt)}</Table.Td>
              <Table.Td>
                <Group justify="flex-end">
                  <Button variant="default" size="xs" onClick={() => onOpen(request)}>
                    Review
                  </Button>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
