'use client';

// The Finance payments page body: Pending, Cleared and Programs tabs.
// Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). Recording opens a centered modal. The Programs tab
// holds the per-program payment toggle. All changes go through ./actions.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Stack, Switch, Table, Tabs, Text, Title } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { setPaymentRequired, type PaymentActionResult } from './actions';
import type { PaymentRow, ProgramSetting } from './queries';
import { RecordPaymentModal } from './RecordPaymentModal';
import { formatClearedDate, formatPeso, type PaymentTab } from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

export function PaymentsAdmin({
  tab,
  rows,
  programs,
}: {
  tab: PaymentTab;
  rows: PaymentRow[];
  programs: ProgramSetting[];
}) {
  const router = useRouter();
  const [open, setOpen] = useState<PaymentRow | null>(null);
  const [message, setMessage] = useState<PaymentActionResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  function setTab(next: string | null) {
    setMessage(null);
    router.replace(next === 'cleared' || next === 'programs' ? `/finance/payments?tab=${next}` : '/finance/payments');
  }

  async function toggle(program: ProgramSetting, required: boolean) {
    if (busy) return;
    setBusy(program.programId);
    setMessage(null);
    setMessage(await setPaymentRequired(program.programId, required));
    setBusy(null);
  }

  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Payments</Title>

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="pending">Pending</Tabs.Tab>
          <Tabs.Tab value="cleared">Cleared</Tabs.Tab>
          <Tabs.Tab value="programs">Programs</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      {message && (
        <Text size="sm" c={'error' in message ? color.error : color.success} role="status">
          {'error' in message ? message.error : message.message}
        </Text>
      )}

      <Divider />

      {tab === 'pending' && <PendingRows rows={rows} onOpen={setOpen} />}
      {tab === 'cleared' && <ClearedRows rows={rows} />}
      {tab === 'programs' && <ProgramRows programs={programs} busy={busy} onToggle={toggle} />}

      {open && (
        <RecordPaymentModal
          row={open}
          onClose={() => setOpen(null)}
          onDone={(result) => {
            setOpen(null);
            setMessage(result);
          }}
        />
      )}
    </Stack>
  );
}

function PendingRows({ rows, onOpen }: { rows: PaymentRow[]; onOpen: (row: PaymentRow) => void }) {
  if (rows.length === 0) return <Text c={color.textSecondary}>No payment is waiting.</Text>;

  if (rows.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rows.map((row, index) => (
          <Stack key={row.studentId} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>
                  {row.studentNumber}, {row.fullName}
                </Text>
                <Text size="sm" c={color.textSecondary}>
                  {row.section}
                </Text>
              </Stack>
              <Button variant="default" onClick={() => onOpen(row)}>
                Record
              </Button>
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={720}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Student number</Table.Th>
            <Table.Th>Student</Table.Th>
            <Table.Th>Section</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((row) => (
            <Table.Tr key={row.studentId}>
              <Table.Td>{row.studentNumber}</Table.Td>
              <Table.Td>{row.fullName}</Table.Td>
              <Table.Td>{row.section}</Table.Td>
              <Table.Td>
                <Group justify="flex-end">
                  <Button variant="default" size="xs" onClick={() => onOpen(row)}>
                    Record
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

function ClearedRows({ rows }: { rows: PaymentRow[] }) {
  if (rows.length === 0) return <Text c={color.textSecondary}>No payment has been recorded yet.</Text>;

  if (rows.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rows.map((row, index) => (
          <Stack key={row.studentId} gap={spacing.xs}>
            {index > 0 && <Divider />}
            <Text fw={fontWeight.semibold}>
              {row.studentNumber}, {row.fullName}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {row.section}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              Paid {formatPeso(row.amountPaid)} of {formatPeso(row.amountDue ?? 0)}
              {row.receiptNo ? `, receipt ${row.receiptNo}` : ''}
              {row.clearedAt ? `, ${formatClearedDate(row.clearedAt)}` : ''}
            </Text>
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
            <Table.Th>Student number</Table.Th>
            <Table.Th>Student</Table.Th>
            <Table.Th>Section</Table.Th>
            <Table.Th>Amount due</Table.Th>
            <Table.Th>Amount paid</Table.Th>
            <Table.Th>Receipt</Table.Th>
            <Table.Th>Cleared</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((row) => (
            <Table.Tr key={row.studentId}>
              <Table.Td>{row.studentNumber}</Table.Td>
              <Table.Td>{row.fullName}</Table.Td>
              <Table.Td>{row.section}</Table.Td>
              <Table.Td>{formatPeso(row.amountDue ?? 0)}</Table.Td>
              <Table.Td>{formatPeso(row.amountPaid)}</Table.Td>
              <Table.Td>{row.receiptNo ?? ''}</Table.Td>
              <Table.Td>{row.clearedAt ? formatClearedDate(row.clearedAt) : ''}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function ProgramRows({
  programs,
  busy,
  onToggle,
}: {
  programs: ProgramSetting[];
  busy: string | null;
  onToggle: (program: ProgramSetting, required: boolean) => void;
}) {
  if (programs.length === 0) return <Text c={color.textSecondary}>No program is set up yet.</Text>;

  const note = (
    <Text size="sm" c={color.textSecondary}>
      A change applies to slips issued from now on. Slips already issued keep their own setting.
    </Text>
  );

  if (programs.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {note}
        {programs.map((program, index) => (
          <Stack key={program.programId} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Group justify="space-between" wrap="nowrap">
              <Stack gap={spacing.xs}>
                <Text fw={fontWeight.semibold}>{program.code}</Text>
                <Text size="sm" c={color.textSecondary}>
                  {program.name}
                </Text>
              </Stack>
              <Switch
                label="Payment required"
                checked={program.paymentRequired}
                disabled={busy !== null}
                onChange={(event) => onToggle(program, event.currentTarget.checked)}
              />
            </Group>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Stack gap={spacing.md}>
      {note}
      <Table.ScrollContainer minWidth={720}>
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Program</Table.Th>
              <Table.Th>Name</Table.Th>
              <Table.Th>Payment required</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {programs.map((program) => (
              <Table.Tr key={program.programId}>
                <Table.Td>{program.code}</Table.Td>
                <Table.Td>{program.name}</Table.Td>
                <Table.Td>
                  <Switch
                    aria-label={`Payment required for ${program.code}`}
                    checked={program.paymentRequired}
                    disabled={busy !== null}
                    onChange={(event) => onToggle(program, event.currentTarget.checked)}
                  />
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Stack>
  );
}
