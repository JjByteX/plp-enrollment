'use client';

import { useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Box, Button, Card, Divider, Group, Menu, NavLink, Stack, Text, Tooltip, UnstyledButton, useComputedColorScheme } from '@mantine/core';
import { ChevronDoubleLeftIcon, ChevronDoubleRightIcon, Cog6ToothIcon } from '@heroicons/react/24/outline';
import { signOut } from '@/lib/auth/actions';
import { SIDEBAR_COOKIE, flattenNav, isActive, type NavGroup, type NavItem } from '@/lib/nav';
import { NAV_ICONS } from '@/components/NavIcons';
import { NextStepCard } from '@/features/next-step-card/NextStepCard';
import type { NextStep } from '@/features/next-step-card/queries';
import { CommandSearch } from '@/features/search/CommandSearch';
import { SettingsModal } from '@/features/settings/SettingsModal';
import { SettingsProvider } from '@/features/settings/SettingsContext';
import { WithdrawMyEnrollmentModal } from '@/features/withdraw-enrollment/WithdrawMyEnrollmentModal';
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
// one linear path, shown by the next step card. An Applicant or Student who has not
// been issued a COR also gets "Withdraw enrollment" in the profile menu (step 17).
export function PortalShell({
  userName,
  roleLabel,
  homeHref,
  nav,
  defaultCollapsed,
  nextStep,
  canWithdraw,
  children,
}: {
  userName: string;
  roleLabel: string;
  homeHref: string;
  nav: NavGroup[];
  defaultCollapsed: boolean;
  nextStep: NextStep;
  canWithdraw: boolean;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(defaultCollapsed);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const hasSidebar = nav.length > 0;
  const searchItems = flattenNav(nav);
  const scheme = useComputedColorScheme('light');
  const isDark = scheme === 'dark';
  const chromeBg = isDark ? color.surfacePageDark : color.surfaceChrome;
  const pageBg = isDark ? color.surfaceCardDark : color.surfacePage;
  const pageBorder = isDark ? color.borderDark : color.border;
  const textPrimary = isDark ? color.textPrimaryDark : color.textPrimary;
  const textSecondary = isDark ? color.textSecondaryDark : color.textSecondary;

  function toggle() {
    const next = !collapsed;
    setCollapsed(next);
    document.cookie = `${SIDEBAR_COOKIE}=${next ? 'collapsed' : 'expanded'}; path=/; max-age=${COOKIE_MAX_AGE}; samesite=lax`;
  }

  const brand = (
    <Link href={homeHref} style={{ textDecoration: 'none', color: 'inherit' }}>
      <Group gap={spacing.sm} wrap="nowrap" style={{ overflow: 'hidden' }}>
        <Image src="/plp-logo.png" alt="PLP seal" width={LOGO_SIZE} height={LOGO_SIZE} style={{ flex: 'none' }} />
        <Text fw={fontWeight.semibold} c={textPrimary} style={{ whiteSpace: 'nowrap' }}>
          PLP Enrollment
        </Text>
      </Group>
    </Link>
  );

  // One sidebar entry. An entry with subpages (Admin's staff areas) expands to
  // show them; on the collapsed rail it opens a small menu beside the icon.
  function renderItem(item: NavItem) {
    const Icon = NAV_ICONS[item.icon];
    const children = item.children ?? [];
    const active = children.length > 0 ? pathname === item.href : isActive(pathname, item);
    const styles = {
      root: { justifyContent: collapsed ? 'center' : undefined },
      section: { marginInlineEnd: collapsed ? 'unset' : undefined },
      label: { color: active ? green[7] : textPrimary },
    };

    if (children.length > 0 && collapsed) {
      return (
        <Menu key={item.href} trigger="hover" openDelay={60} closeDelay={150} position="right-start" offset={spacing.sm} withinPortal>
          <Menu.Target>
            <NavLink
              component={Link}
              href={item.href}
              aria-label={item.label}
              leftSection={<Icon width={layout.iconSize} height={layout.iconSize} />}
              active={isActive(pathname, item)}
              variant="light"
              color="green"
              style={{ borderRadius: radius.default }}
              styles={styles}
            />
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Label>{item.label}</Menu.Label>
            <Menu.Item component={Link} href={item.href}>
              Home
            </Menu.Item>
            {children.map((child) => {
              const ChildIcon = NAV_ICONS[child.icon];
              return (
                <Menu.Item
                  key={child.href}
                  component={Link}
                  href={child.href}
                  leftSection={<ChildIcon width={layout.iconSize} height={layout.iconSize} />}
                >
                  {child.label}
                </Menu.Item>
              );
            })}
          </Menu.Dropdown>
        </Menu>
      );
    }

    const link = (
      <NavLink
        key={item.href}
        component={Link}
        href={item.href}
        label={collapsed ? undefined : item.label}
        aria-label={item.label}
        leftSection={<Icon width={layout.iconSize} height={layout.iconSize} />}
        active={active}
        defaultOpened={children.length > 0 && isActive(pathname, item)}
        childrenOffset={spacing.lg}
        variant="light"
        color="green"
        fw={fontWeight.regular}
        style={{ borderRadius: radius.default }}
        styles={styles}
      >
        {children.length > 0 ? children.map((child) => renderItem(child)) : undefined}
      </NavLink>
    );
    return collapsed ? (
      <Tooltip key={item.href} label={item.label} position="right">
        {link}
      </Tooltip>
    ) : (
      link
    );
  }

  const profileMenu = (
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
              <Text size="sm" fw={fontWeight.semibold} c={textPrimary}>
                {userName}
              </Text>
            </Group>
          </UnstyledButton>
        </Menu.Target>
        <Menu.Dropdown>
          <Menu.Label>{roleLabel}</Menu.Label>
          <Menu.Item leftSection={<Cog6ToothIcon width={layout.iconSize} height={layout.iconSize} />} onClick={() => setSettingsOpen(true)}>
            Settings
          </Menu.Item>
          {canWithdraw && (
            <Menu.Item color={color.error} onClick={() => setWithdrawOpen(true)}>
              Withdraw enrollment
            </Menu.Item>
          )}
          <Menu.Divider />
          <Menu.Item onClick={() => signOut()}>Sign out</Menu.Item>
        </Menu.Dropdown>
      </Menu>
  );

  return (
    <SettingsProvider>
      <Box style={{ display: 'flex', flexDirection: 'column', height: '100dvh', background: chromeBg }}>
        <Box
          component="header"
          h={layout.headerHeight}
          px={spacing.sm}
          style={{ flex: 'none', display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center', columnGap: spacing.md }}
        >
          <Box pl={spacing.sm} style={{ flex: 'none', justifySelf: 'start' }}>
            {brand}
          </Box>
          <Box style={{ minWidth: 0 }}>{searchItems.length > 0 && <CommandSearch items={searchItems} />}</Box>
          <Box style={{ justifySelf: 'end' }}>{profileMenu}</Box>
        </Box>

        <Box style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        {hasSidebar && (
          <Box
            component="nav"
            aria-label="Main"
            px={spacing.sm}
            pb={spacing.sm}
            style={{
              display: 'flex',
              flexDirection: 'column',
              flex: 'none',
              width: collapsed ? layout.sidebarCollapsedWidth : layout.sidebarWidth,
              transition: 'width 150ms ease',
              overflowY: 'auto',
              overflowX: 'hidden',
            }}
          >
            <Stack gap={spacing.md} style={{ flex: 1 }}>
              {nav.map((group, index) => (
                <Stack key={group.label ?? `group-${index}`} gap={spacing.xs}>
                  {index > 0 && <Divider />}
                  {!collapsed && group.label && (
                    <Text size="sm" c={textSecondary} px={spacing.sm} fw={fontWeight.semibold}>
                      {group.label}
                    </Text>
                  )}
                  {group.items.map((item) => renderItem(item))}
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
              c={textSecondary}
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
          {settingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} />}
          {canWithdraw && <WithdrawMyEnrollmentModal opened={withdrawOpen} onClose={() => setWithdrawOpen(false)} />}

          <Box
            component="main"
            p={padding.pageDesktop}
            style={{
              flex: 1,
              overflowY: 'auto',
              background: pageBg,
              border: `1px solid ${pageBorder}`,
              borderRadius: radius.prominent,
              color: textPrimary,
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
      </Box>
    </SettingsProvider>
  );
}
