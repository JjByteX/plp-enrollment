'use client';

// Record one payment, in a centered modal (a focused form that fits one
// screen). The button stays disabled until the input is valid, and the reason
// is shown. Finance may enter an amount due of 0 (nothing to pay).
import { useState } from 'react';
import { NumberInput, Stack, Text, TextInput } from '@mantine/core';
import { color, fontWeight, spacing } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { asNumber, reasonOf } from '@/lib/validate';
import { recordPayment, type PaymentActionResult } from './actions';
import type { PaymentRow } from './queries';
import { MAX_AMOUNT, MAX_RECEIPT, parsePaymentInput } from './schema';

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
  const { loading, error, run } = useFormAction(onDone);

  const parsed = parsePaymentInput({
    studentId: row.studentId,
    amountDue: asNumber(amountDue),
    amountPaid: asNumber(amountPaid),
    receiptNo,
  });

  function onSubmit() {
    if (!parsed.ok) return;
    void run(() => recordPayment(parsed.value));
  }

  return (
    <FormModal
      title="Record payment"
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel="Record payment"
      submitDisabled={!parsed.ok}
    >
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
    </FormModal>
  );
}
