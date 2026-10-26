'use client';

// components/FormModal.tsx
//
// The shared shell of a focused form in a centered modal (a form that fits one
// screen): the modal, the error line, the reason the input is not valid yet,
// and the Cancel and Save row. The fields go in as children. Nothing can be
// closed by a click outside while the request is running.
//
// useFormAction holds the loading and error state and runs the action: it
// ignores a second submit while one is running, shows the error when the
// action refuses, and calls onDone when it succeeds.
import { useState, type ReactNode } from 'react';
import { Button, Group, Modal, Stack, Text } from '@mantine/core';
import { color, padding, spacing } from '@/styles/tokens';

type ActionResult = { error: string } | { ok: true };

function failed(result: ActionResult): result is { error: string } {
  return 'error' in result;
}

export function useFormAction<R extends ActionResult>(onDone: (result: R) => void) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Resolves true when the action succeeded (onDone has been called).
  async function run(action: () => Promise<R>): Promise<boolean> {
    if (loading) return false;
    setLoading(true);
    setError(null);
    const result = await action();
    setLoading(false);
    if (failed(result)) {
      setError(result.error);
      return false;
    }
    onDone(result);
    return true;
  }

  function clearError() {
    setError(null);
  }

  return { loading, error, run, clearError };
}

export function FormModal({
  opened = true,
  title,
  size,
  onClose,
  onSubmit,
  loading,
  error,
  hint,
  submitLabel,
  submitDisabled = false,
  submitColor,
  footer,
  children,
}: {
  opened?: boolean;
  title: string;
  size?: string | number;
  onClose: () => void;
  onSubmit: () => void;
  loading: boolean;
  error: string | null;
  hint?: string | null; // why the Save button is disabled, when it is
  submitLabel: string;
  submitDisabled?: boolean;
  submitColor?: string;
  footer?: ReactNode; // below the Cancel and Save row
  children: ReactNode;
}) {
  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title={title}
      size={size}
      padding={padding.modal}
      radius="lg"
      closeOnClickOutside={!loading}
    >
      <form
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit();
        }}
      >
        <Stack gap={spacing.md}>
          {children}
          {error && (
            <Text size="sm" c={color.error} role="alert">
              {error}
            </Text>
          )}
          {hint && (
            <Text size="sm" c={color.textSecondary}>
              {hint}
            </Text>
          )}
          <Group justify="space-between">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" color={submitColor} loading={loading} disabled={submitDisabled}>
              {submitLabel}
            </Button>
          </Group>
          {footer}
        </Stack>
      </form>
    </Modal>
  );
}
