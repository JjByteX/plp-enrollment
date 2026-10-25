'use client';

import { AppShell, Button, Card, Group, Menu, Stack, Title } from '@mantine/core';
import { signOut } from '@/lib/auth/actions';
import { NextStepCard } from '@/features/next-step-card/NextStepCard';
import type { NextStep } from '@/features/next-step-card/queries';

// Shell per ux-ui-guidelines.md: header, nav area, and the persistent
// "Your next step" card slot. Nav links are filled in by later build steps.
// The profile menu sits top right and holds Sign out.
export function PortalShell({
  userName,
  roleLabel,
  nextStep,
  children,
}: {
  userName: string;
  roleLabel: string;
  nextStep: NextStep;
  children: React.ReactNode;
}) {
  return (
    <AppShell header={{ height: 60 }} padding="md">
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Title order={4}>PLP Enrollment</Title>
          <Menu position="bottom-end">
            <Menu.Target>
              <Button variant="subtle">{userName}</Button>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Label>{roleLabel}</Menu.Label>
              <Menu.Item onClick={() => signOut()}>Sign out</Menu.Item>
            </Menu.Dropdown>
          </Menu>
        </Group>
      </AppShell.Header>
      <AppShell.Main>
        <Stack gap="md">
          {nextStep.kind !== 'staff' && (
            <Card withBorder radius="md" p="md" data-slot="next-step-card">
              <NextStepCard step={nextStep} />
            </Card>
          )}
          {children}
        </Stack>
      </AppShell.Main>
    </AppShell>
  );
}
