// components/ListOrTable.tsx
//
// Fewer than 5 rows render as a list, 5 or more as a table
// (ux-ui-guidelines.md). Shared so each admin page states only what differs:
// how one row reads as a list item, and what the table columns are. The empty
// message stays with the caller, because its wording is specific to the page.
import type { CSSProperties, ReactNode } from 'react';
import { Divider, Stack, Table } from '@mantine/core';
import { spacing } from '@/styles/tokens';

export const LIST_LIMIT = 5; // fewer rows than this is a list, not a table

export type ListColumn<T> = {
  header: ReactNode; // leave empty for an actions column
  cell: (row: T) => ReactNode;
  style?: CSSProperties; // applied to each cell of this column
};

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
            {columns.map((column, index) => (
              <Table.Th key={index}>{column.header}</Table.Th>
            ))}
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((row) => (
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
