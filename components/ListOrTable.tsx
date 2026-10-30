// components/ListOrTable.tsx
//
// Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). Shared so each admin page states only what differs:
// how one row reads as a list item, and what the table columns are. The empty
// message stays with the caller, because its wording is specific to the page.
//
// SORTING
// ───────
// Table headers sort on click: ascending, then descending, then back to the
// unsorted order the caller passed in (its own default order, e.g. newest
// first) — cycling through the clicked column's state only, same as a
// spreadsheet. The header shows a chevron: up when ascending, down when
// descending, up-and-down (muted) when the column is sortable but not the
// active one. A column opts out with `sortable: false` (its header renders as
// plain text, same as a column with no `header`); every other column sorts
// by default.
//
// Cells often render a formatted node (a Badge, a `Text` with a different
// string than the raw field, a button). Sorting cannot read that back out of
// a React node, so each column gives its own comparison value: `sortValue`
// when the column needs one (a formatted date, a precomputed label, a value
// that differs from what `cell` shows), falling back to `cell`'s own return
// value when `cell` already returns a plain string or number (true for most
// columns here). A column with neither (an actions column, a free-text
// reason) should not be sortable and must set `sortable: false`.
//
// The list form (fewer than 5 rows) never shows a sort control — the ux-ui
// list/table split is for display density, not for adding a second
// interaction model to five rows a person can already scan.
//
// This is a client-side sort over the `rows` array the caller passed in. For
// a page that paginates on the server (its own `total` from the server, not
// `rows.length`), this only orders the rows already on the current page, same
// as every other client-side behavior in this component — see AuditLogView,
// the one caller with server pagination.
import { useMemo, useReducer, type CSSProperties, type ReactNode } from 'react';
import { Divider, Stack, Table, UnstyledButton } from '@mantine/core';
import { ChevronUpIcon, ChevronDownIcon, ChevronUpDownIcon } from '@heroicons/react/24/outline';
import { color, layout, spacing } from '@/styles/tokens';

export const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

export type ListColumn<T> = {
  header: ReactNode; // leave empty for an actions column
  cell: (row: T) => ReactNode;
  style?: CSSProperties; // applied to each cell of this column
  /** Defaults to true. Set false for an actions column or any column whose
   * cell has no sensible raw value to compare (e.g. a free-form node). */
  sortable?: boolean;
  /** The value to sort by. Defaults to `cell(row)` when omitted, which only
   * works when `cell` returns a plain string or number — give this whenever
   * `cell` renders a node or a differently-formatted string. */
  sortValue?: (row: T) => string | number | null | undefined;
};

type SortDir = 'asc' | 'desc';
type SortState = { index: number | null; dir: SortDir };

const SORT_INITIAL: SortState = { index: null, dir: 'asc' };

function sortReducer(state: SortState, clickedIndex: number): SortState {
  if (state.index !== clickedIndex) return { index: clickedIndex, dir: 'asc' };
  if (state.dir === 'asc') return { index: clickedIndex, dir: 'desc' };
  return SORT_INITIAL;
}

function compareValues(a: string | number, b: string | number, dir: SortDir): number {
  const cmp =
    typeof a === 'number' && typeof b === 'number'
      ? a - b
      : String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
  return dir === 'asc' ? cmp : -cmp;
}

function SortIcon({ active, dir }: { active: boolean; dir: SortDir }) {
  const style = { width: layout.iconSize, height: layout.iconSize };
  if (!active) return <ChevronUpDownIcon style={style} color={color.textSecondary} />;
  return dir === 'asc' ? (
    <ChevronUpIcon style={style} color={color.textPrimary} />
  ) : (
    <ChevronDownIcon style={style} color={color.textPrimary} />
  );
}

export function ListOrTable<T>({
  rows,
  rowKey,
  item,
  columns,
  minWidth,
  itemGap = spacing.sm,
}: {
  rows: T[];
  rowKey: (row: T) => string;
  item: (row: T) => ReactNode; // one row as a list item, without its divider
  columns: ListColumn<T>[];
  minWidth: number; // the table scrolls sideways below this width
  itemGap?: number; // space inside one list item
}) {
  const [sortState, dispatchSort] = useReducer(sortReducer, SORT_INITIAL);

  const sortedRows = useMemo(() => {
    if (sortState.index === null) return rows;
    const column = columns[sortState.index];
    if (!column) return rows;
    const valueOf = column.sortValue ?? ((row: T) => column.cell(row) as unknown as string | number | null | undefined);
    return [...rows].sort((a, b) => {
      const av = valueOf(a) ?? '';
      const bv = valueOf(b) ?? '';
      return compareValues(av, bv, sortState.dir);
    });
    // columns is treated as stable for a given page (defined inline per
    // render, but same shape every time); only the clicked index and
    // direction, and the rows themselves, should re-trigger the sort.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, sortState.index, sortState.dir]);

  if (rows.length < LIST_LIMIT) {
    return (
      <Stack gap={spacing.md}>
        {rows.map((row, index) => (
          <Stack key={rowKey(row)} gap={itemGap}>
            {index > 0 && <Divider />}
            {item(row)}
          </Stack>
        ))}
      </Stack>
    );
  }

  return (
    <Table.ScrollContainer minWidth={minWidth}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            {columns.map((column, index) => {
              const isSortable = column.sortable !== false && !!column.header;
              const isActive = isSortable && sortState.index === index;
              if (!isSortable) {
                return <Table.Th key={index}>{column.header}</Table.Th>;
              }
              return (
                <Table.Th key={index} aria-sort={isActive ? (sortState.dir === 'asc' ? 'ascending' : 'descending') : 'none'}>
                  <UnstyledButton
                    onClick={() => dispatchSort(index)}
                    aria-label={`Sort by ${String(column.header)}`}
                    style={{ display: 'inline-flex', alignItems: 'center', gap: spacing.xs }}
                  >
                    {column.header}
                    <SortIcon active={isActive} dir={sortState.dir} />
                  </UnstyledButton>
                </Table.Th>
              );
            })}
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {sortedRows.map((row) => (
            <Table.Tr key={rowKey(row)}>
              {columns.map((column, index) => (
                <Table.Td key={index} style={column.style}>
                  {column.cell(row)}
                </Table.Td>
              ))}
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
