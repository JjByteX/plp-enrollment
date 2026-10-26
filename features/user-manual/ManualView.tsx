'use client';

// features/user-manual/ManualView.tsx
//
// The user manual page body. A long reference read top to bottom, so it is a
// full page (ux-ui-guidelines.md, Help & FAQ): the section index sits beside
// the text on desktop and becomes a "Jump to" select on mobile. Sections are
// separated by dividers, not cards. Tables with fewer than 5 rows render as a
// list, as everywhere else in the app. The index marks the section being read,
// and the text can link to other sections (#id) and to pages (/path).
import { Fragment, useEffect, useState } from 'react';
import Link from 'next/link';
import { Anchor, Box, Divider, List, NavLink, Select, Stack, Table, Text, Title } from '@mantine/core';
import { color, fontWeight, layout, radius, spacing } from '@/styles/tokens';
import type { Block, Manual } from './parse';

const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

// **bold** and [text](target) pieces are picked out of the text. Split with a
// capture group puts those pieces at the odd positions. A target starting with
// # jumps to a section; one starting with / opens a page.
const INLINE_PIECE = /(\*\*.+?\*\*|\[[^\]]+\]\([^)]+\))/;
const LINK_PIECE = /^\[([^\]]+)\]\(([^)]+)\)$/;

function InlineLink({ label, href }: { label: string; href: string }) {
  if (href.startsWith('/')) {
    return (
      <Anchor component={Link} href={href} inherit>
        {label}
      </Anchor>
    );
  }
  return (
    <Anchor href={href} inherit>
      {label}
    </Anchor>
  );
}

function Inline({ text }: { text: string }) {
  let offset = 0; // where each piece starts in the text, so its key stays the same on re-render
  return (
    <>
      {text.split(INLINE_PIECE).map((part, position) => {
        const key = offset;
        offset += part.length;
        if (position % 2 === 0) return <Fragment key={key}>{part}</Fragment>;
        const link = LINK_PIECE.exec(part);
        if (link) return <InlineLink key={key} label={link[1] ?? ''} href={link[2] ?? ''} />;
        return (
          <Text key={key} span inherit fw={fontWeight.semibold}>
            {part.slice(2, -2)}
          </Text>
        );
      })}
    </>
  );
}

function BlockView({ block }: { block: Block }) {
  switch (block.type) {
    case 'h3':
      return (
        <Text fw={fontWeight.semibold} component="h3" m={0}>
          {block.text}
        </Text>
      );
    case 'p':
      return (
        <Text>
          <Inline text={block.text} />
        </Text>
      );
    case 'ul':
    case 'ol':
      return (
        <List type={block.type === 'ol' ? 'ordered' : 'unordered'} spacing={spacing.sm} withPadding>
          {block.items.map((item) => (
            <List.Item key={item.text}>
              <Inline text={item.text} />
              {item.sub.length > 0 && (
                <List listStyleType="disc" spacing={spacing.xs} mt={spacing.xs}>
                  {item.sub.map((sub) => (
                    <List.Item key={sub}>
                      <Inline text={sub} />
                    </List.Item>
                  ))}
                </List>
              )}
            </List.Item>
          ))}
        </List>
      );
    case 'table':
      return block.rows.length < LIST_LIMIT ? (
        <Stack gap={spacing.md}>
          {block.rows.map((row, rowIndex) => (
            <Stack key={row.key} gap={spacing.xs}>
              {rowIndex > 0 && <Divider mb={spacing.sm} />}
              <Text fw={fontWeight.semibold}>
                <Inline text={row.cells[0]?.text ?? ''} />
              </Text>
              {row.cells.slice(1).map(
                (cell, cellIndex) =>
                  cell.text !== '' && (
                    <Text key={cell.key} size="sm" c={color.textSecondary}>
                      {block.head[cellIndex + 1]}: <Inline text={cell.text} />
                    </Text>
                  )
              )}
            </Stack>
          ))}
        </Stack>
      ) : (
        <Table.ScrollContainer minWidth={layout.manualTableMinWidth}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                {block.head.map((cell, index) => (
                  <Table.Th key={index}>{cell}</Table.Th>
                ))}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {block.rows.map((row) => (
                <Table.Tr key={row.key}>
                  {row.cells.map((cell) => (
                    <Table.Td key={cell.key}>
                      <Inline text={cell.text} />
                    </Table.Td>
                  ))}
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      );
    default:
      return null;
  }
}

export function ManualView({ manual }: { manual: Manual }) {
  const jumpOptions = manual.sections.map((section) => ({ value: section.id, label: section.title }));
  const [activeId, setActiveId] = useState<string | null>(manual.sections[0]?.id ?? null);

  // The section nearest the top of the screen is the one being read.
  useEffect(() => {
    const visible = new Set<string>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) visible.add(entry.target.id);
          else visible.delete(entry.target.id);
        }
        const current = manual.sections.find((section) => visible.has(section.id));
        if (current) setActiveId(current.id);
      },
      { rootMargin: '0px 0px -60% 0px' }
    );
    for (const section of manual.sections) {
      const element = document.getElementById(section.id);
      if (element) observer.observe(element);
    }
    return () => observer.disconnect();
  }, [manual.sections]);

  return (
    <Stack gap={spacing.lg}>
      <Title order={3}>User manual</Title>

      <Box style={{ display: 'flex', alignItems: 'flex-start', gap: spacing.xl }}>
        <Box
          component="nav"
          aria-label="Manual sections"
          visibleFrom="md"
          style={{
            flex: 'none',
            width: layout.manualIndexWidth,
            position: 'sticky',
            top: spacing.xl,
            maxHeight: `calc(100vh - ${layout.headerHeight * 2}px)`,
            overflowY: 'auto',
            paddingRight: spacing.md,
            borderRight: `1px solid ${color.border}`,
          }}
        >
          <Stack gap={spacing.xs}>
            <Text size="xs" fw={fontWeight.semibold} c={color.textSecondary} tt="uppercase">
              Contents
            </Text>
            {manual.sections.map((section) => (
              <NavLink
                key={section.id}
                component="a"
                href={`#${section.id}`}
                label={section.title}
                active={section.id === activeId}
                onClick={() => setActiveId(section.id)}
                fw={section.id === activeId ? fontWeight.semibold : fontWeight.regular}
                style={{ borderRadius: radius.default }}
              />
            ))}
          </Stack>
        </Box>

        <Stack gap={spacing.xl} style={{ flex: 1, minWidth: 0, maxWidth: layout.readingWidth }}>
          <Select
            hiddenFrom="md"
            label="Jump to"
            placeholder="Choose a section"
            data={jumpOptions}
            allowDeselect={false}
            onChange={(value) => {
              if (value) window.location.hash = value;
            }}
          />

          {manual.intro.length > 0 && (
            <Stack gap={spacing.md}>
              {manual.intro.map((block) => (
                <BlockView key={block.key} block={block} />
              ))}
            </Stack>
          )}

          {manual.sections.map((section) => (
            <Stack key={section.id} id={section.id} gap={spacing.xl} style={{ scrollMarginTop: spacing.xl }}>
              <Divider />
              <Stack gap={spacing.md}>
                <Title order={4}>{section.title}</Title>
                {section.blocks.map((block) => (
                  <BlockView key={block.key} block={block} />
                ))}
              </Stack>
            </Stack>
          ))}
        </Stack>
      </Box>
    </Stack>
  );
}
