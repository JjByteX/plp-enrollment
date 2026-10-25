'use client';

// features/settings/SettingsContext.tsx
//
// App-wide display settings: font size (a scale applied to the document root,
// so every rem-based Mantine size scales with it) and color theme (delegates
// to Mantine's own light/dark/auto scheme). Both persist to localStorage so
// they survive a reload; applied via a layout-level effect, not per component.
import { useMantineColorScheme, type MantineColorScheme } from '@mantine/core';
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

const FONT_SCALE_KEY = 'plp_font_scale';
const ROOT_FONT_SIZE_PX = 16; // Mantine's default root size; our scale multiplies this.

export const FONT_SCALE_MIN = 0.85;
export const FONT_SCALE_MAX = 1.3;
export const FONT_SCALE_STEP = 0.05;
export const FONT_SCALE_DEFAULT = 1;

// Named marks shown under the slider, per ux-ui-guidelines.md (plain, few
// steps, no invented scale). Maps to Mantine's own Small/Medium/Large voice.
export const FONT_SCALE_MARKS = [
  { value: 0.85, label: 'Small' },
  { value: 1, label: 'Default' },
  { value: 1.15, label: 'Large' },
  { value: 1.3, label: 'X-Large' },
];

function clampScale(value: number): number {
  return Math.min(FONT_SCALE_MAX, Math.max(FONT_SCALE_MIN, value));
}

type SettingsContextValue = {
  fontScale: number;
  setFontScale: (value: number) => void;
  colorScheme: MantineColorScheme;
  setColorScheme: (value: MantineColorScheme) => void;
};

const SettingsContext = createContext<SettingsContextValue | null>(null);

export function SettingsProvider({ children }: { children: React.ReactNode }) {
  const { colorScheme, setColorScheme } = useMantineColorScheme();
  const [fontScale, setFontScaleState] = useState(FONT_SCALE_DEFAULT);

  // Read the saved scale once on mount (after hydration, so SSR markup still
  // matches the first client render) and apply it to the document root.
  useEffect(() => {
    const saved = window.localStorage.getItem(FONT_SCALE_KEY);
    const parsed = saved ? Number.parseFloat(saved) : FONT_SCALE_DEFAULT;
    const initial = Number.isFinite(parsed) ? clampScale(parsed) : FONT_SCALE_DEFAULT;
    setFontScaleState(initial);
    document.documentElement.style.fontSize = `${ROOT_FONT_SIZE_PX * initial}px`;
  }, []);

  const setFontScale = useCallback((value: number) => {
    const next = clampScale(value);
    setFontScaleState(next);
    document.documentElement.style.fontSize = `${ROOT_FONT_SIZE_PX * next}px`;
    window.localStorage.setItem(FONT_SCALE_KEY, String(next));
  }, []);

  const value = useMemo(
    () => ({ fontScale, setFontScale, colorScheme, setColorScheme }),
    [fontScale, setFontScale, colorScheme, setColorScheme],
  );

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings(): SettingsContextValue {
  const ctx = useContext(SettingsContext);
  if (!ctx) throw new Error('useSettings must be used within SettingsProvider');
  return ctx;
}
