'use client';

// The Grading tab of the Admin Content page (step 19): the bands and the
// incomplete window. A short list of bands, one row each; editing opens a
// centered modal. The save button stays disabled until the scale is valid and
// the reason is shown (two bands that overlap are named).
import { useState, type FormEvent } from 'react';
import { Button, Divider, Group, Modal, NumberInput, Select, Stack, Switch, Table, Text, TextInput } from '@mantine/core';
import { color, fontWeight, padding, spacing } from '@/styles/tokens';
import { saveScale, type GradingActionResult } from './actions';
import { MAX_BAND_LABEL, MAX_INC_DAYS, OUTCOMES, OUTCOME_LABEL, parseScale, type Band, type Outcome, type Scale } from './schema';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

const OUTCOME_OPTIONS = OUTCOMES.map((value) => ({ value, label: OUTCOME_LABEL[value] }));

function range(band: Band): string {
  if (band.from === null || band.to === null) return '';
  return band.from === band.to ? String(band.from) : `${band.from} to ${band.to}`;
}

export function GradingTab({ scale, onDone }: { scale: Scale; onDone: (result: GradingActionResult) => void }) {
  const [editing, setEditing] = useState(false);

  return (
    <Stack gap={spacing.md}>
      <Group justify="space-between" align="flex-end">
        <Stack gap={spacing.xs}>
          <Text c={color.textSecondary}>
            {scale.bands.some((band) => !band.descriptive)
              ? 'Grades are matched to these bands.'
              : 'No grading scale is set. Professors cannot enter grades until one is.'}
          </Text>
          <Text size="sm" c={color.textSecondary}>
            An incomplete that is not completed within {scale.incWindowDays} days becomes a failed 5.0.
          </Text>
        </Stack>
        <Button onClick={() => setEditing(true)}>Edit scale</Button>
      </Group>
      <Divider />
      <BandRows bands={scale.bands} />
      {editing && (
        <ScaleModal
          scale={scale}
          onClose={() => setEditing(false)}
          onDone={(result) => {
            setEditing(false);
            onDone(result);
          }}
        />
      )}
    </Stack>
  );
}

function BandRows({ bands }: { bands: Band[] }) {
  if (bands.length === 0) return <Text c={color.textSecondary}>No band is set up yet.</Text>;

  if (bands.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {bands.map((band, index) => (
          <Stack key={band.label} gap={spacing.sm}>
            {index > 0 && <Divider />}
            <Stack gap={spacing.xs}>
              <Text fw={fontWeight.semibold}>{band.label}</Text>
              <Text size="sm" c={color.textSecondary}>
                {[OUTCOME_LABEL[band.outcome], range(band), band.descriptive ? 'display only' : ''].filter(Boolean).join(', ')}
              </Text>
            </Stack>
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={480}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Label</Table.Th>
            <Table.Th>Outcome</Table.Th>
            <Table.Th>Numbers</Table.Th>
            <Table.Th>Use</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {bands.map((band) => (
            <Table.Tr key={band.label}>
              <Table.Td>{band.label}</Table.Td>
              <Table.Td>{OUTCOME_LABEL[band.outcome]}</Table.Td>
              <Table.Td>{range(band)}</Table.Td>
              <Table.Td>{band.descriptive ? 'Display only' : 'Decides the outcome'}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

type Draft = { label: string; outcome: string | null; descriptive: boolean; from: number | string; to: number | string };

function toDraft(band: Band): Draft {
  return { label: band.label, outcome: band.outcome, descriptive: band.descriptive, from: band.from ?? '', to: band.to ?? '' };
}

function num(value: number | string): number | null {
  return typeof value === 'number' ? value : null;
}

function ScaleModal({
  scale,
  onClose,
  onDone,
}: {
  scale: Scale;
  onClose: () => void;
  onDone: (result: GradingActionResult) => void;
}) {
  const [rows, setRows] = useState<Draft[]>(scale.bands.map(toDraft));
  const [days, setDays] = useState<number | string>(scale.incWindowDays);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseScale({
    incWindowDays: typeof days === 'number' ? days : Number.NaN,
    bands: rows.map((row) => ({
      label: row.label,
      outcome: row.outcome ?? '',
      descriptive: row.descriptive,
      from: num(row.from),
      to: num(row.to),
    })),
  });

  function change(index: number, patch: Partial<Draft>) {
    setRows((current) => current.map((row, i) => (i === index ? { ...row, ...patch } : row)));
  }

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok || loading) return;
    setLoading(true);
    setError(null);
    const result = await saveScale(parsed.value);
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      return;
    }
    onDone(result);
  }

  return (
    <Modal opened onClose={onClose} title="Edit grading scale" size="xl" padding={padding.modal} radius="lg" closeOnClickOutside={!loading}>
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <NumberInput
            label="Days an incomplete stays open"
            description="After this, an incomplete that is not completed becomes a failed 5.0."
            value={days}
            onChange={setDays}
            min={1}
            max={MAX_INC_DAYS}
            allowDecimal={false}
            allowNegative={false}
            required
          />
          <Divider />
          {rows.length === 0 && <Text c={color.textSecondary}>No band yet. Add the first one.</Text>}
          {rows.map((row, index) => (
            <Stack key={index} gap={spacing.sm}>
              {index > 0 && <Divider />}
              <Group grow align="flex-start" gap={spacing.md}>
                <TextInput
                  label="Label"
                  value={row.label}
                  onChange={(event) => change(index, { label: event.currentTarget.value })}
                  maxLength={MAX_BAND_LABEL}
                  required
                />
                {!row.descriptive && (
                  <Select
                    label="Outcome"
                    data={OUTCOME_OPTIONS}
                    value={row.outcome}
                    onChange={(value) => change(index, { outcome: value as Outcome | null })}
                    allowDeselect={false}
                    required
                  />
                )}
              </Group>
              <Group grow align="flex-start" gap={spacing.md}>
                <NumberInput label="From" decimalScale={2} allowNegative={false} value={row.from} onChange={(value) => change(index, { from: value })} />
                <NumberInput label="To" decimalScale={2} allowNegative={false} value={row.to} onChange={(value) => change(index, { to: value })} />
              </Group>
              <Group justify="space-between">
                <Switch
                  label="Display only (does not decide the outcome)"
                  checked={row.descriptive}
                  onChange={(event) => change(index, { descriptive: event.currentTarget.checked })}
                />
                <Button variant="subtle" size="xs" color={color.error} onClick={() => setRows((current) => current.filter((_, i) => i !== index))}>
                  Remove band
                </Button>
              </Group>
            </Stack>
          ))}
          <Group justify="flex-start">
            <Button variant="default" onClick={() => setRows((current) => [...current, { label: '', outcome: null, descriptive: false, from: '', to: '' }])}>
              Add band
            </Button>
          </Group>
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
              Save scale
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
