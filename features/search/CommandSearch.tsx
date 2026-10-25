'use client';

// features/search/CommandSearch.tsx
//
// Centered top-bar search over the areas recommended to the signed-in user —
// exactly the items already in their sidebar (lib/nav.ts), never the whole
// site map. Fuzzy and typo-tolerant (Fuse.js): "shedules", "corr", "paymnet"
// all still find their page. Arrow keys move the highlight, Enter navigates,
// Escape closes.
//
// Typing two or more characters also looks inside the pages: students,
// applicants, accounts, sections, subjects and rooms by name or number
// (./actions, under the person's own session so row level security decides
// what they can see). Pages come first, records follow.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Fuse from 'fuse.js';
import { Box, Group, Kbd, Paper, Stack, Text, TextInput, UnstyledButton } from '@mantine/core';
import { MagnifyingGlassIcon } from '@heroicons/react/24/outline';
import { useHotkeys, useClickOutside } from '@mantine/hooks';
import { color, fontWeight, layout, radius, shadow, spacing } from '@/styles/tokens';
import { NAV_ICONS } from '@/components/NavIcons';
import type { NavItem } from '@/lib/nav';
import { searchRecords, type RecordHit } from './actions';

const MAX_RESULTS = 8;
const MIN_RECORD_CHARS = 2;
const DEBOUNCE_MS = 250;

type Entry = { key: string; label: string; detail?: string; kind?: string; href: string; icon: NavItem['icon'] };

export function CommandSearch({ items }: { items: NavItem[] }) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [highlighted, setHighlighted] = useState(0);
  const [records, setRecords] = useState<RecordHit[]>([]);
  const requestId = useRef(0);
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

  // Records are fetched after a short pause in typing; a slower, older answer
  // never replaces a newer one.
  useEffect(() => {
    const trimmed = query.trim();
    const id = ++requestId.current;
    if (trimmed.length < MIN_RECORD_CHARS) {
      setRecords([]);
      return;
    }
    const timer = setTimeout(() => {
      searchRecords(trimmed)
        .then((hits) => {
          if (id === requestId.current) setRecords(hits);
        })
        .catch(() => {
          if (id === requestId.current) setRecords([]);
        });
    }, DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query]);

  const results = useMemo<Entry[]>(() => {
    const trimmed = query.trim();
    const pages: Entry[] = (
      trimmed ? fuse.search(trimmed).slice(0, MAX_RESULTS).map((result) => result.item) : items.slice(0, MAX_RESULTS)
    ).map((item) => ({ key: item.href, label: item.label, href: item.href, icon: item.icon }));
    return trimmed.length >= MIN_RECORD_CHARS ? [...pages, ...records] : pages;
  }, [query, fuse, items, records]);

  function go(item: Entry) {
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
        placeholder="Search pages and records…"
        aria-label="Search pages and records"
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
                  key={item.key}
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
                    {item.detail && (
                      <Text size="xs" c={color.textSecondary} style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {item.kind ? `${item.kind} · ` : ''}
                        {item.detail}
                      </Text>
                    )}
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
