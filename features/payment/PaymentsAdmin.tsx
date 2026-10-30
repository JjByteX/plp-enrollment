'use client';

// The Finance payments page body: Pending, Cleared and Programs tabs.
// Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). Recording opens a centered modal. The Programs tab
// holds the per-program payment toggle. All changes go through ./actions.
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, Divider, Group, Stack, Switch, Tabs, Text } from '@mantine/core';
import { PageHeading } from '@/components/PageHeading';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormMessage } from '@/components/FormMessage';
import { ListOrTable } from '@/components/ListOrTable';
import { useSectionFilter } from '@/components/SectionFilter';
import { StatLine } from '@/components/StatLine';
import { formatDate, formatPeso } from '@/lib/format';
import { setPaymentRequired, type PaymentActionResult } from './actions';
import type { PaymentRow, ProgramSetting } from './queries';
import { RecordPaymentModal } from './RecordPaymentModal';
import type { PaymentTab } from './schema';

export function PaymentsAdmin({
  tab,
  rows,
  programs,
  stats,
}: {
  tab: PaymentTab;
  rows: PaymentRow[];
  programs: ProgramSetting[];
  stats: { pending: number; cleared: number; collected: number } | null; // null on the Programs tab
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
      <PageHeading title="Payments" parent={{ label: 'Finance', href: '/finance' }} />

      {stats && (
        <StatLine
          stats={[
            { value: stats.pending, label: 'pending' },
            { value: stats.cleared, label: 'cleared' },
            { value: formatPeso(stats.collected), label: 'collected this term' },
          ]}
        />
      )}

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="pending">Pending</Tabs.Tab>
          <Tabs.Tab value="cleared">Cleared</Tabs.Tab>
          <Tabs.Tab value="programs">Programs</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <FormMessage message={message} />

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

function PendingRows({ rows: all, onOpen }: { rows: PaymentRow[]; onOpen: (row: PaymentRow) => void }) {
  const sectionFilter = useSectionFilter(all);
  if (all.length === 0) return <Text c={color.textSecondary}>No payment is waiting.</Text>;
  const rows = sectionFilter.apply(all);

  return (
    <Stack gap={spacing.md}>
    {sectionFilter.control}
    {rows.length === 0 ? <Text c={color.textSecondary}>No payment in this section is waiting.</Text> : <ListOrTable
      rows={rows}
      rowKey={(row) => row.studentId}
      minWidth={720}
      item={(row) => (
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
      )}
      columns={[
        { header: 'Student number', cell: (row) => row.studentNumber },
        { header: 'Student', cell: (row) => row.fullName },
        { header: 'Section', cell: (row) => row.section },
        {
          header: '',
          cell: (row) => (
            <Group justify="flex-end">
              <Button variant="default" size="xs" onClick={() => onOpen(row)}>
                Record
              </Button>
            </Group>
          ),
        },
      ]}
    />}
    </Stack>
  );
}

function ClearedRows({ rows: all }: { rows: PaymentRow[] }) {
  const sectionFilter = useSectionFilter(all);
  if (all.length === 0) return <Text c={color.textSecondary}>No payment has been recorded yet.</Text>;
  const rows = sectionFilter.apply(all);

  return (
    <Stack gap={spacing.md}>
    {sectionFilter.control}
    {rows.length === 0 ? <Text c={color.textSecondary}>No payment in this section has been recorded.</Text> : <ListOrTable
      rows={rows}
      rowKey={(row) => row.studentId}
      minWidth={900}
      itemGap={spacing.xs}
      item={(row) => (
        <>
          <Text fw={fontWeight.semibold}>
            {row.studentNumber}, {row.fullName}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            {row.section}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            Paid {formatPeso(row.amountPaid)} of {formatPeso(row.amountDue ?? 0)}
            {row.receiptNo ? `, receipt ${row.receiptNo}` : ''}
            {row.clearedAt ? `, ${formatDate(row.clearedAt)}` : ''}
          </Text>
        </>
      )}
      columns={[
        { header: 'Student number', cell: (row) => row.studentNumber },
        { header: 'Student', cell: (row) => row.fullName },
        { header: 'Section', cell: (row) => row.section },
        { header: 'Amount due', cell: (row) => formatPeso(row.amountDue ?? 0) },
        { header: 'Amount paid', cell: (row) => formatPeso(row.amountPaid) },
        { header: 'Receipt', cell: (row) => row.receiptNo ?? '' },
        { header: 'Cleared', cell: (row) => (row.clearedAt ? formatDate(row.clearedAt) : '') },
      ]}
    />}
    </Stack>
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

  return (
    <Stack gap={spacing.md}>
      <Text size="sm" c={color.textSecondary}>
        A change applies to slips issued from now on. Slips already issued keep their own setting.
      </Text>
      <ListOrTable
        rows={programs}
        rowKey={(program) => program.programId}
        minWidth={720}
        item={(program) => (
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
        )}
        columns={[
          { header: 'Program', cell: (program) => program.code },
          { header: 'Name', cell: (program) => program.name },
          {
            header: 'Payment required',
            cell: (program) => (
              <Switch
                aria-label={`Payment required for ${program.code}`}
                checked={program.paymentRequired}
                disabled={busy !== null}
                onChange={(event) => onToggle(program, event.currentTarget.checked)}
              />
            ),
          },
        ]}
      />
    </Stack>
  );
}
