// features/user-manual/parse.ts
//
// Turns the manual's markdown text into plain blocks. It handles only what the
// manual uses: headings, paragraphs, bullet and numbered lists (one nested
// level), pipe tables and **bold** (bold is read at render time).

export type ListItem = { text: string; sub: string[] };

export type Block =
  | { type: 'h2'; text: string; id: string }
  | { type: 'h3'; text: string }
  | { type: 'p'; text: string }
  | { type: 'ul' | 'ol'; items: ListItem[] }
  | { type: 'table'; head: string[]; rows: string[][] };

export type Section = { id: string; title: string; blocks: Block[] };
export type Manual = { intro: Block[]; sections: Section[] };

const LIST_LINE = /^(\s*)(-|\d+\.)\s+(.*)$/;

function slug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function cells(line: string): string[] {
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
      blocks.push({ type: 'h2', text, id: slug(text) });
      i += 1;
    } else if (line.startsWith('### ')) {
      blocks.push({ type: 'h3', text: line.slice(4).trim() });
      i += 1;
    } else if (trimmed.startsWith('|')) {
      const rows: string[] = [];
      while (i < lines.length && (lines[i] ?? '').trim().startsWith('|')) {
        rows.push(lines[i] ?? '');
        i += 1;
      }
      blocks.push({ type: 'table', head: cells(rows[0] ?? ''), rows: rows.slice(2).map(cells) });
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
      blocks.push({ type: kind, items });
    } else {
      const parts: string[] = [];
      while (i < lines.length && !startsNewBlock(lines[i] ?? '')) {
        parts.push((lines[i] ?? '').trim());
        i += 1;
      }
      blocks.push({ type: 'p', text: parts.join(' ') });
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
