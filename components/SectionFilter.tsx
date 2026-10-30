'use client';

// components/SectionFilter.tsx
//
// A Section dropdown for lists of students. Give it every row the page can
// show: it offers each distinct section, and apply() narrows a list to the
// chosen one. With fewer than two sections there is nothing to choose, so the
// control is null and apply() returns the list as it is.
import { useState, type ReactNode } from 'react';
import { Select } from '@mantine/core';

export function useSectionFilter(rows: { section: string | null }[]): {
  control: ReactNode;
  active: boolean;
  apply: <T extends { section: string | null }>(list: T[]) => T[];
} {
  const [chosen, setChosen] = useState<string | null>(null);

  const sections = Array.from(new Set(rows.map((row) => row.section).filter((name): name is string => !!name))).sort();
  const active = chosen !== null && sections.includes(chosen);

  const control =
    sections.length < 2 ? null : (
      <Select
        label="Section"
        placeholder="All sections"
        data={sections}
        value={active ? chosen : null}
        onChange={setChosen}
        clearable
        searchable
        w={220}
      />
    );

  return {
    control,
    active,
    apply: (list) => (active ? list.filter((row) => row.section === chosen) : list),
  };
}
