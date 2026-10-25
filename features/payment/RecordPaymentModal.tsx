'use client';

// Record one payment, in a centered modal (a focused form that fits one
// screen). The button stays disabled until the input is valid, and the reason
// is shown. Finance may enter an amount due of 0 (nothing to pay).
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, NumberInput, Stack, Text, TextInput } from '@mantine/core';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import { recordPayment, type PaymentActionResult } from './actions';
import type { PaymentRow } from './queries';
import { MAX_AMOUNT, MAX_RECEIPT, parsePaymentInput } from './schema';

function asNumber(value: number | string): number {
  return typeof value === 'number' ? value : Number.NaN;
}

export function RecordPaymentModal({
  row,
  onClose,
  onDone,
}: {
  row: PaymentRow;
  onClose: () => void;
  onDone: (result: PaymentActionResult) => void;
}) {
  const [amountDue, setAmountDue] = useState<number | string>('');
  const [amountPaid, setAmountPaid] = useState<number | string>('');
  const [receiptNo, setReceiptNo] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parsePaymentInput({
    studentId: row.studentId,
    amountDue: asNumber(amountDue),
    amountPaid: asNumber(amountPaid),
    receiptNo,
  });

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || loading) return;
    setLoading(true);
    setError(null);
    const result = await recordPayment(parsed.value);
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onDone(result);
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title="Record payment"
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <Stack gap={spacing.xs}>
            <Text fw={fontWeight.semibold}>
              {row.studentNumber}, {row.fullName}
            </Text>
            <Text size="sm" c={color.textSecondary}>
              {row.section}
            </Text>
          </Stack>
          <NumberInput
            label="Amount due"
            prefix="₱"
            thousandSeparator=","
            decimalScale={2}
            min={0}
            max={MAX_AMOUNT}
            allowNegative={false}
            value={amountDue}
            onChange={setAmountDue}
            required
          />
          <NumberInput
            label="Amount paid"
            description="Must cover the amount due. Partial payments are not recorded."
            prefix="₱"
            thousandSeparator=","
            decimalScale={2}
            min={0}
            max={MAX_AMOUNT}
            allowNegative={false}
            value={amountPaid}
            onChange={setAmountPaid}
            required
          />
          <TextInput
            label="Receipt number"
            value={receiptNo}
            onChange={(event) => setReceiptNo(event.currentTarget.value)}
            maxLength={MAX_RECEIPT}
          />
          {error && (
            <Text size="sm" c={color.error} role="alert">
              {error}
            </Text>
          )}
          {!parsed.ok && (
            <Text size="sm" c={color.textSecondary}>
              {parsed.reason}
            </Text>
          )}
          <Group justify="space-between">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading} disabled={!parsed.ok}>
              Record payment
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
