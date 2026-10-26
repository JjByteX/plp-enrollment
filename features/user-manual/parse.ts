// features/user-manual/parse.ts
//
// Turns the manual's markdown text into plain blocks. It handles only what the
// manual uses: headings, paragraphs, bullet and numbered lists (one nested
// level), pipe tables and **bold** (bold is read at render time).

export type ListItem = { text: string; sub: string[] };

export type TableCell = { key: string; text: string };
export type TableRow = { key: string; cells: TableCell[] };

// Every block carries a key made when the text is parsed, so React lists can
// use it instead of the position in the array.
export type Block = { key: string } & (
  | { type: 'h2'; text: string; id: string }
  | { type: 'h3'; text: string }
  | { type: 'p'; text: string }
  | { type: 'ul' | 'ol'; items: ListItem[] }
  | { type: 'table'; head: string[]; rows: TableRow[] }
);

export type Section = { id: string; title: string; blocks: Block[] };
export type Manual = { intro: Block[]; sections: Section[] };

// The text group starts at a non-space, so it cannot overlap the spaces before it
// (an overlap makes the match slow on long runs of spaces). It is undefined for
// an empty item.
const LIST_LINE = /^(\s*)(-|\d+\.)\s+(\S.*)?$/;

function slug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, ''); // the line above leaves at most one dash at each end
}

function splitCells(line: string): string[] {
  return line
    .trim()
    .replace(/^\||\|$/g, '')
    .split('|')
    .map((cell) => cell.trim());
}

function startsNewBlock(line: string): boolean {
  const trimmed = line.trim();
  return trimmed === '' || trimmed === '---' || trimmed.startsWith('#') || trimmed.startsWith('|') || LIST_LINE.test(line);
}

function parseBlocks(source: string): Block[] {
  const lines = source.split('\n');
  const blocks: Block[] = [];
  let i = 0;
  let nextKey = 0;
  const makeKey = (prefix: string) => `${prefix}${nextKey++}`;

  while (i < lines.length) {
    const line = lines[i] ?? '';
    const trimmed = line.trim();

    if (trimmed === '' || trimmed === '---') {
      i += 1;
    } else if (line.startsWith('# ')) {
      // The page has its own heading, so the manual's title line is dropped.
      i += 1;
    } else if (line.startsWith('## ')) {
      const text = line.slice(3).trim();
      blocks.push({ key: makeKey('b'), type: 'h2', text, id: slug(text) });
      i += 1;
    } else if (line.startsWith('### ')) {
      blocks.push({ key: makeKey('b'), type: 'h3', text: line.slice(4).trim() });
      i += 1;
    } else if (trimmed.startsWith('|')) {
      const rows: string[] = [];
      while (i < lines.length && (lines[i] ?? '').trim().startsWith('|')) {
        rows.push(lines[i] ?? '');
        i += 1;
      }
      const tableKey = makeKey('b');
      const body = rows.slice(2).map((row, rowNumber) => {
        const rowKey = `${tableKey}-r${rowNumber}`;
        return {
          key: rowKey,
          cells: splitCells(row).map((text, cellNumber) => ({ key: `${rowKey}-c${cellNumber}`, text })),
        };
      });
      blocks.push({ key: tableKey, type: 'table', head: splitCells(rows[0] ?? ''), rows: body });
    } else if (LIST_LINE.test(line)) {
      const kind = /^\d/.test(trimmed) ? 'ol' : 'ul';
      const items: ListItem[] = [];
      while (i < lines.length) {
        const match = LIST_LINE.exec(lines[i] ?? '');
        if (!match) break;
        const indent = (match[1] ?? '').length;
        const text = match[3] ?? '';
        const last = items[items.length - 1];
        if (indent > 0 && last) {
          last.sub.push(text);
        } else if ((/^\d/.test(match[2] ?? '') ? 'ol' : 'ul') === kind) {
          items.push({ text, sub: [] });
        } else {
          break;
        }
        i += 1;
      }
      blocks.push({ key: makeKey('b'), type: kind, items });
    } else {
      const parts: string[] = [];
      while (i < lines.length && !startsNewBlock(lines[i] ?? '')) {
        parts.push((lines[i] ?? '').trim());
        i += 1;
      }
      blocks.push({ key: makeKey('b'), type: 'p', text: parts.join(' ') });
    }
  }

  return blocks;
}

export function parseManual(source: string): Manual {
  const intro: Block[] = [];
  const sections: Section[] = [];

  for (const block of parseBlocks(source)) {
    if (block.type === 'h2') {
      sections.push({ id: block.id, title: block.text, blocks: [] });
    } else {
      const current = sections[sections.length - 1];
      (current ? current.blocks : intro).push(block);
    }
  }

  return { intro, sections };
}
