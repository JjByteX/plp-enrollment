'use client';

import { AppShell, Button, Card, Group, Menu, Stack, Text, Title } from '@mantine/core';
import { signOut } from '@/lib/auth/actions';

// Shell per ux-ui-guidelines.md: header, nav area, and the persistent
// "Your next step" card slot. Nav links and the card content are filled in
// by later build steps. The profile menu sits top right and holds Sign out.
export function PortalShell({
  userName,
  roleLabel,
  children,
}: {
  userName: string;
  roleLabel: string;
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
          <Card withBorder radius="md" p="md" data-slot="next-step-card">
            <Text fw={600}>Your next step</Text>
            <Text c="dimmed" size="sm">
              Nothing to do yet.
            </Text>
          </Card>
          {children}
        </Stack>
      </AppShell.Main>
    </AppShell>
  );
}
