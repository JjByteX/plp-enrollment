'use client';

import { AppShell, Card, Group, Stack, Text, Title } from '@mantine/core';

// Shell per ux-ui-guidelines.md: header, nav area, and the persistent
// "Your next step" card slot. Nav links and the card content are filled in
// by later build steps.
export function PortalShell({ children }: { children: React.ReactNode }) {
  return (
    <AppShell header={{ height: 60 }} padding="md">
      <AppShell.Header>
        <Group h="100%" px="md">
          <Title order={4}>PLP Enrollment</Title>
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
