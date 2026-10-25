'use client';

// features/search/CommandSearch.tsx
//
// Centered top-bar search over the areas recommended to the signed-in user —
// exactly the items already in their sidebar (lib/nav.ts), never the whole
// site map. Fuzzy and typo-tolerant (Fuse.js): "shedules", "corr", "paymnet"
// all still find their page. Arrow keys move the highlight, Enter navigates,
// Escape closes.
import { useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Fuse from 'fuse.js';
import { Box, Group, Kbd, Paper, Stack, Text, TextInput, UnstyledButton } from '@mantine/core';
import { MagnifyingGlassIcon } from '@heroicons/react/24/solid';
import { useHotkeys, useClickOutside } from '@mantine/hooks';
import { color, fontWeight, layout, radius, shadow, spacing } from '@/styles/tokens';
import { NAV_ICONS } from '@/components/NavIcons';
import type { NavItem } from '@/lib/nav';

const MAX_RESULTS = 8;

export function CommandSearch({ items }: { items: NavItem[] }) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [highlighted, setHighlighted] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useClickOutside(() => setOpen(false), null, [containerRef.current]);
  useHotkeys([['mod+K', () => inputRef.current?.focus()], ['/', () => inputRef.current?.focus()]]);

  // Typo-tolerant: a generous threshold plus matching on label and a few
  // keystroke-saving synonyms per area, so near-misses ("shedule", "corr",
  // "paymnet") and abbreviations ("cor") still resolve.
  const fuse = useMemo(
    () =>
      new Fuse(items, {
        keys: [
          { name: 'label', weight: 0.7 },
          { name: 'keywords', weight: 0.3 },
        ],
        threshold: 0.4,
        distance: 100,
        ignoreLocation: true,
        includeScore: true,
      }),
    [items],
  );

  const results = useMemo(() => {
    const trimmed = query.trim();
    if (!trimmed) return items.slice(0, MAX_RESULTS);
    return fuse
      .search(trimmed)
      .slice(0, MAX_RESULTS)
      .map((result) => result.item);
  }, [query, fuse, items]);

  function go(item: NavItem) {
    router.push(item.href);
    setOpen(false);
    setQuery('');
    inputRef.current?.blur();
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (!open) return;
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setHighlighted((current) => Math.min(current + 1, Math.max(results.length - 1, 0)));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setHighlighted((current) => Math.max(current - 1, 0));
    } else if (event.key === 'Enter') {
      event.preventDefault();
      const target = results[highlighted];
      if (target) go(target);
    } else if (event.key === 'Escape') {
      setOpen(false);
      inputRef.current?.blur();
    }
  }

  if (items.length === 0) return null;

  return (
    <Box ref={containerRef} style={{ position: 'relative', width: 'min(480px, 100%)' }}>
      <TextInput
        ref={inputRef}
        value={query}
        onChange={(event) => {
          setQuery(event.currentTarget.value);
          setHighlighted(0);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onKeyDown={onKeyDown}
        placeholder="Search your areas…"
        aria-label="Search your areas"
        leftSection={<MagnifyingGlassIcon width={layout.iconSize} height={layout.iconSize} />}
        rightSection={
          !query && (
            <Kbd size="xs" c={color.textSecondary}>
              /
            </Kbd>
          )
        }
        rightSectionWidth={40}
        radius={radius.default}
      />

      {open && results.length > 0 && (
        <Paper
          withBorder
          radius={radius.default}
          p={spacing.xs}
          style={{
            position: 'absolute',
            top: '100%',
            marginTop: spacing.xs,
            left: 0,
            right: 0,
            zIndex: 200,
            boxShadow: shadow.floating,
            background: color.surfacePage,
          }}
        >
          <Stack gap={2}>
            {results.map((item, index) => {
              const Icon = NAV_ICONS[item.icon];
              const active = index === highlighted;
              return (
                <UnstyledButton
                  key={item.href}
                  onMouseEnter={() => setHighlighted(index)}
                  onClick={() => go(item)}
                  p={spacing.sm}
                  style={{
                    borderRadius: radius.default,
                    background: active ? color.accentSubtleBg : 'transparent',
                  }}
                >
                  <Group gap={spacing.sm} wrap="nowrap">
                    <Icon width={layout.iconSize} height={layout.iconSize} color={color.textSecondary} />
                    <Text size="sm" fw={fontWeight.regular} c={color.textPrimary}>
                      {item.label}
                    </Text>
                  </Group>
                </UnstyledButton>
              );
            })}
          </Stack>
        </Paper>
      )}

      {open && query.trim().length > 0 && results.length === 0 && (
        <Paper
          withBorder
          radius={radius.default}
          p={spacing.md}
          style={{
            position: 'absolute',
            top: '100%',
            marginTop: spacing.xs,
            left: 0,
            right: 0,
            zIndex: 200,
            boxShadow: shadow.floating,
            background: color.surfacePage,
          }}
        >
          <Text size="sm" c={color.textSecondary}>
            No matches for &ldquo;{query}&rdquo;.
          </Text>
        </Paper>
      )}
    </Box>
  );
}
