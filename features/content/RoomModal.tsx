'use client';

// Add or edit one room, in a centered modal. Capacity and college are
// optional. Deleting asks once more first, and the database refuses it while
// a section uses the room.
import { useState } from 'react';
import { Button, Group, NumberInput, Select, Text, TextInput } from '@mantine/core';
import { color, spacing } from '@/styles/tokens';
import { FormModal, useFormAction } from '@/components/FormModal';
import { numberOrNull, reasonOf } from '@/lib/validate';
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
  const { loading, error, run } = useFormAction(onDone);

  const parsed = parseRoomInput({
    name,
    capacity: numberOrNull(capacity),
    collegeId,
  });

  async function runAction(action: () => Promise<ContentActionResult>) {
    if (!(await run(action))) setConfirmDelete(false);
  }

  function onSubmit() {
    if (!parsed.ok) return;
    void runAction(() => saveRoom(room?.id ?? null, parsed.value));
  }

  return (
    <FormModal
      title={room ? 'Edit room' : 'Add room'}
      onClose={onClose}
      onSubmit={onSubmit}
      loading={loading}
      error={error}
      hint={reasonOf(parsed)}
      submitLabel={room ? 'Save' : 'Add room'}
      submitDisabled={!parsed.ok}
      footer={
        room && (
          <Group justify="flex-start">
            {confirmDelete ? (
              <Group gap={spacing.sm}>
                <Text size="sm">Delete this room?</Text>
                <Button
                  variant="default"
                  size="xs"
                  color={color.error}
                  disabled={loading}
                  onClick={() => void runAction(() => deleteRoom(room.id))}
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
        )
      }
    >
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
    </FormModal>
  );
}
