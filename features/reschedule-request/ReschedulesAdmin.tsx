'use client';

// The Registrar's reschedules page body: the requests waiting for an answer,
// and the mass reschedule. Fewer than 5 requests render as a list, 5 or more
// as a table (ux-ui-guidelines.md). Answering opens a centered modal. All
// changes go through the feature actions.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Stack, Tabs, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import { ListOrTable } from '@/components/ListOrTable';
import { formatDate } from '@/lib/format';
import { MassReschedulePanel } from '@/features/reschedule-mass/MassReschedulePanel';
import type { BookedVisit } from '@/features/reschedule-mass/queries';
import type { SlotRow } from '@/features/visit-scheduling/queries';
import type { RescheduleActionResult } from './actions';
import { DecideRescheduleModal } from './DecideRescheduleModal';
import type { PendingRequest } from './queries';
import { formatSlotDate, windowLabel } from './schema';

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
      <PageHeading title="Reschedules" parent={{ label: 'Registrar', href: '/registrar' }} />

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="requests">Requests</Tabs.Tab>
          <Tabs.Tab value="mass">Mass reschedule</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <FormMessage message={message} />

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

  return (
    <ListOrTable
      rows={requests}
      rowKey={(request) => request.requestId}
      minWidth={900}
      item={(request) => (
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
      )}
      columns={[
        { header: 'Applicant', cell: (request) => `${request.fullName} (${request.applicantRef})` },
        { header: 'Program', cell: (request) => request.programCode },
        { header: 'Visit', cell: visitText },
        {
          header: 'Reason',
          cell: (request) => (
            <Text size="sm" lineClamp={2}>
              {request.reason}
            </Text>
          ),
          sortValue: (request) => request.reason,
        },
        { header: 'Sent', cell: (request) => formatDate(request.requestedAt), sortValue: (request) => request.requestedAt },
        {
          header: '',
          cell: (request) => (
            <Group justify="flex-end">
              <Button variant="default" size="xs" onClick={() => onOpen(request)}>
                Review
              </Button>
            </Group>
          ),
          sortable: false,
        },
      ]}
    />
  );
}
