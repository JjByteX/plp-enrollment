'use client';

// components/FormMessage.tsx
//
// The line that tells the person what an action did: the message in the
// success colour, or the error in the error colour. Announced politely to
// screen readers (role="status"). Renders nothing when there is no message.
import { Text } from '@mantine/core';
import { color } from '@/styles/tokens';

export type FormMessageValue = { error: string } | { message: string };

export function FormMessage({ message }: { message: FormMessageValue | null | undefined }) {
  if (!message) return null;
  const failed = 'error' in message;
  return (
    <Text size="sm" c={failed ? color.error : color.success} role="status">
      {failed ? message.error : message.message}
    </Text>
  );
}
