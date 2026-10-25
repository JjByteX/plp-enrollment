'use client';

import { useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Box, Button, Card, Divider, Group, Menu, NavLink, Stack, Text, Tooltip, UnstyledButton } from '@mantine/core';
import { ChevronDoubleLeftIcon, ChevronDoubleRightIcon } from '@heroicons/react/24/outline';
import { signOut } from '@/lib/auth/actions';
import { SIDEBAR_COOKIE, isActive, type NavGroup } from '@/lib/nav';
import { NAV_ICONS } from '@/components/NavIcons';
import { NextStepCard } from '@/features/next-step-card/NextStepCard';
import type { NextStep } from '@/features/next-step-card/queries';
import { color, fontWeight, green, layout, padding, radius, spacing } from '@/styles/tokens';

const LOGO_SIZE = 32;
const COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const letters = parts.length > 1 ? parts[0][0] + parts[parts.length - 1][0] : (parts[0] ?? '?').slice(0, 2);
  return letters.toUpperCase();
}

// Shell per ux-ui-guidelines.md: sidebar, top bar with the profile menu, and
// the persistent "Your next step" card slot. The frame is a flat grey; the page
// sits on one rounded white panel. The sidebar collapses to a narrow rail and
// the choice is kept in a cookie so the server renders it the same way next time.
// Roles with no nav groups (Applicant, Student) get no sidebar: their flow is
// one linear path, shown by the next step card.
export function PortalShell({
  userName,
  roleLabel,
  homeHref,
  nav,
  defaultCollapsed,
  nextStep,
  children,
}: {
  userName: string;
  roleLabel: string;
  homeHref: string;
  nav: NavGroup[];
  defaultCollapsed: boolean;
  nextStep: NextStep;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(defaultCollapsed);
  const hasSidebar = nav.length > 0;

  function toggle() {
    const next = !collapsed;
    setCollapsed(next);
    document.cookie = `${SIDEBAR_COOKIE}=${next ? 'collapsed' : 'expanded'}; path=/; max-age=${COOKIE_MAX_AGE}; samesite=lax`;
  }

  const brand = (
    <Link href={homeHref} style={{ textDecoration: 'none', color: 'inherit' }}>
      <Group gap={spacing.sm} wrap="nowrap">
        <Image src="/plp-logo.png" alt="PLP seal" width={LOGO_SIZE} height={LOGO_SIZE} />
        {!collapsed && (
          <Text fw={fontWeight.semibold} c={color.textPrimary}>
            PLP Enrollment
          </Text>
        )}
      </Group>
    </Link>
  );

  return (
    <Box style={{ display: 'flex', height: '100dvh', background: color.surfaceChrome }}>
      {hasSidebar && (
        <Box
          component="nav"
          aria-label="Main"
          p={spacing.sm}
          style={{
            display: 'flex',
            flexDirection: 'column',
            flex: 'none',
            width: collapsed ? layout.sidebarCollapsedWidth : layout.sidebarWidth,
            transition: 'width 150ms ease',
            overflowY: 'auto',
          }}
        >
          <Box p={spacing.sm} mb={spacing.md} style={{ display: 'flex', justifyContent: collapsed ? 'center' : 'flex-start' }}>
            {brand}
          </Box>

          <Stack gap={spacing.md} style={{ flex: 1 }}>
            {nav.map((group, index) => (
              <Stack key={group.label ?? `group-${index}`} gap={spacing.xs}>
                {collapsed && index > 0 && <Divider />}
                {!collapsed && group.label && (
                  <Text size="sm" c={color.textSecondary} px={spacing.sm} fw={fontWeight.semibold}>
                    {group.label}
                  </Text>
                )}
                {group.items.map((item) => {
                  const Icon = NAV_ICONS[item.icon];
                  const active = isActive(pathname, item);
                  const link = (
                    <NavLink
                      key={item.href}
                      component={Link}
                      href={item.href}
                      label={collapsed ? undefined : item.label}
                      aria-label={item.label}
                      leftSection={<Icon width={layout.iconSize} height={layout.iconSize} />}
                      active={active}
                      variant="light"
                      color="green"
                      fw={fontWeight.regular}
                      style={{ borderRadius: radius.default }}
                      styles={{
                        root: { justifyContent: collapsed ? 'center' : undefined },
                        section: { marginInlineEnd: collapsed ? 'unset' : undefined },
                        label: { color: active ? green[7] : color.textPrimary },
                      }}
                    />
                  );
                  return collapsed ? (
                    <Tooltip key={item.href} label={item.label} position="right">
                      {link}
                    </Tooltip>
                  ) : (
                    link
                  );
                })}
              </Stack>
            ))}
          </Stack>

          <Button
            variant="subtle"
            color="gray"
            onClick={toggle}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            aria-expanded={!collapsed}
            justify={collapsed ? 'center' : 'flex-start'}
            fullWidth
            c={color.textSecondary}
          >
            {collapsed ? (
              <ChevronDoubleRightIcon width={layout.iconSize} height={layout.iconSize} />
            ) : (
              <Group gap={spacing.sm} wrap="nowrap">
                <ChevronDoubleLeftIcon width={layout.iconSize} height={layout.iconSize} />
                Collapse sidebar
              </Group>
            )}
          </Button>
        </Box>
      )}

      <Box style={{ display: 'flex', flexDirection: 'column', flex: 1, minWidth: 0 }} pr={spacing.sm} pb={spacing.sm} pl={hasSidebar ? 0 : spacing.sm}>
        <Group h={layout.headerHeight} justify={hasSidebar ? 'flex-end' : 'space-between'} wrap="nowrap" style={{ flex: 'none' }}>
          {!hasSidebar && <Box pl={spacing.sm}>{brand}</Box>}
          <Menu position="bottom-end">
            <Menu.Target>
              <UnstyledButton aria-label="Profile menu">
                <Group gap={spacing.sm} wrap="nowrap">
                  <Box
                    bg={color.accentSubtleBg}
                    c={green[7]}
                    fw={fontWeight.semibold}
                    style={{
                      width: layout.avatarSize,
                      height: layout.avatarSize,
                      borderRadius: radius.default,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    {initials(userName)}
                  </Box>
                  <Text size="sm" fw={fontWeight.semibold}>
                    {userName}
                  </Text>
                </Group>
              </UnstyledButton>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Label>{roleLabel}</Menu.Label>
              <Menu.Item onClick={() => signOut()}>Sign out</Menu.Item>
            </Menu.Dropdown>
          </Menu>
        </Group>

        <Box
          component="main"
          p={padding.pageDesktop}
          style={{
            flex: 1,
            overflowY: 'auto',
            background: color.surfacePage,
            border: `1px solid ${color.border}`,
            borderRadius: radius.prominent,
          }}
        >
          <Stack gap={spacing.md}>
            {nextStep.kind !== 'staff' && (
              <Card withBorder p={spacing.md} data-slot="next-step-card">
                <NextStepCard step={nextStep} />
              </Card>
            )}
            {children}
          </Stack>
        </Box>
      </Box>
    </Box>
  );
}
