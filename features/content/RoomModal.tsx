'use client';

// Add or edit one room, in a centered modal. Capacity and college are
// optional. Deleting asks once more first, and the database refuses it while
// a section uses the room.
import { useState, type FormEvent } from 'react';
import { Button, Group, Modal, NumberInput, Select, Stack, Text, TextInput } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';
import { deleteRoom, saveRoom, type ContentActionResult } from './actions';
import type { CollegeOption, RoomRow } from './queries';
import { MAX_ROOM_CAPACITY, MAX_ROOM_NAME, parseRoomInput } from './schema';

export function RoomModal({
  room,
  colleges,
  onClose,
  onDone,
}: {
  room: RoomRow | null; // null adds a room
  colleges: CollegeOption[];
  onClose: () => void;
  onDone: (result: ContentActionResult) => void;
}) {
  const [name, setName] = useState(room?.name ?? '');
  const [capacity, setCapacity] = useState<number | string>(room?.capacity ?? '');
  const [collegeId, setCollegeId] = useState<string | null>(room?.collegeId ?? null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const parsed = parseRoomInput({
    name,
    capacity: typeof capacity === 'number' ? capacity : null,
    collegeId,
  });

  async function run(action: () => Promise<ContentActionResult>) {
    if (loading) return;
    setLoading(true);
    setError(null);
    const result = await action();
    setLoading(false);
    if ('error' in result) {
      setError(result.error);
      setConfirmDelete(false);
      return;
    }
    onDone(result);
  }

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!parsed.ok) return;
    void run(() => saveRoom(room?.id ?? null, parsed.value));
  }

  return (
    <Modal
      opened
      onClose={onClose}
      title={room ? 'Edit room' : 'Add room'}
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form onSubmit={onSubmit}>
        <Stack gap={spacing.md}>
          <TextInput
            label="Name"
            value={name}
            onChange={(event) => setName(event.currentTarget.value)}
            maxLength={MAX_ROOM_NAME}
            required
          />
          <NumberInput
            label="Capacity"
            allowDecimal={false}
            allowNegative={false}
            min={1}
            max={MAX_ROOM_CAPACITY}
            value={capacity}
            onChange={setCapacity}
          />
          <Select
            label="College"
            data={colleges.map((college) => ({ value: college.id, label: `${college.code}, ${college.name}` }))}
            value={collegeId}
            onChange={setCollegeId}
            clearable
            searchable
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
              {room ? 'Save' : 'Add room'}
            </Button>
          </Group>
          {room && (
            <Group justify="flex-start">
              {confirmDelete ? (
                <Group gap={spacing.sm}>
                  <Text size="sm">Delete this room?</Text>
                  <Button
                    variant="default"
                    size="xs"
                    color={color.error}
                    disabled={loading}
                    onClick={() => void run(() => deleteRoom(room.id))}
                  >
                    Delete
                  </Button>
                  <Button variant="subtle" size="xs" disabled={loading} onClick={() => setConfirmDelete(false)}>
                    Keep
                  </Button>
                </Group>
              ) : (
                <Button variant="subtle" size="xs" color={color.error} disabled={loading} onClick={() => setConfirmDelete(true)}>
                  Delete room
                </Button>
              )}
            </Group>
          )}
        </Stack>
      </form>
    </Modal>
  );
}
