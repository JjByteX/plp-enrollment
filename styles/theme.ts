// styles/theme.ts
import { createTheme, type MantineColorsTuple } from '@mantine/core';
import { darkScale, gray, green, fontFamily, fontWeight, radius } from './tokens';

// Mantine requires a 10-shade tuple per color. Primer's scales are 11/10
// steps; we map them onto Mantine's 0(lightest)-9(darkest) ordering.
const primerGray: MantineColorsTuple = [
  gray[50],
  gray[100],
  gray[200],
  gray[300],
  gray[400],
  gray[500],
  gray[600],
  gray[700],
  gray[800],
  gray[900],
];

const primerGreen: MantineColorsTuple = [
  green[0],
  green[1],
  green[2],
  green[3],
  green[4],
  green[5],
  green[6],
  green[7],
  green[8],
  green[9],
];

export const theme = createTheme({
  colors: {
    gray: primerGray,
    green: primerGreen,
    dark: [...darkScale] as unknown as MantineColorsTuple,
  },
  primaryColor: 'green',
  primaryShade: 5,
  fontFamily: fontFamily.body,
  headings: {
    fontFamily: fontFamily.heading,
    fontWeight: String(fontWeight.semibold),
  },
  defaultRadius: 'sm', // maps to radius.default (8px) via CSS vars below
  radius: {
    sm: `${radius.default}px`,
    md: `${radius.default}px`,
    lg: `${radius.prominent}px`,
  },
  shadows: {
    // single shadow token, only for floating elements — see tokens.ts
    sm: '0 4px 16px rgba(31, 35, 40, 0.12)',
  },
  components: {
    // Shadows restricted to floating elements only (menus, modals, toasts).
    // Cards, panels, and buttons get no shadow per ux-ui-guidelines.md.
    Card: {
      defaultProps: { shadow: undefined, withBorder: true },
    },
    Paper: {
      defaultProps: { shadow: undefined, withBorder: true },
    },
    // Every modal opens centered (ux-ui-guidelines.md, modal vs panel rule).
    // Set once here so no modal can forget it.
    Modal: {
      defaultProps: { centered: true },
    },
  },
});
