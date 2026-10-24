// styles/tokens.ts
//
// Design tokens for the PLP Enrollment system.
// Source: GitHub Primer's published color primitives (gray + blue scales).
// See decision-log.md, entry #7, for why Primer was chosen over Tailwind
// Slate/Blue — the other option presented to the human.
//
// Per ux-ui-guidelines.md: every color, spacing, radius, and padding value
// used more than once must be a token referenced from here. Never hardcode
// a raw value directly into a component.

// ---------------------------------------------------------------
// COLOR — GitHub Primer neutral (gray) scale, 0 (lightest) to 1000 (darkest)
// ---------------------------------------------------------------
export const gray = {
  0: '#FFFFFF',
  50: '#F6F8FA',
  100: '#EAEEF2',
  200: '#D0D7DE',
  300: '#AFB8C1',
  400: '#8C959F',
  500: '#6E7781',
  600: '#57606A',
  700: '#424A53',
  800: '#32383F',
  900: '#24292F',
  1000: '#1F2328',
} as const;

// GitHub Primer accent (blue) scale, 0 (lightest) to 9 (darkest)
export const blue = {
  0: '#DDF4FF',
  1: '#B6E3FF',
  2: '#80CCFF',
  3: '#54AEFF',
  4: '#218BFF',
  5: '#0969DA', // accent — primary interactive color
  6: '#0550AE',
  7: '#033D8B',
  8: '#0A3069',
  9: '#002155',
} as const;

// ---------------------------------------------------------------
// COLOR — 60/30/10 usage mapping (see ux-ui-guidelines.md Color Rules)
// ---------------------------------------------------------------
export const color = {
  // 60% — dominant surface: page backgrounds
  surfacePage: gray[0],
  surfacePageDark: gray[1000],

  // 30% — secondary surface: cards, panels, sidebars, containers
  surfaceCard: gray[50],
  surfaceCardDark: gray[900],
  border: gray[200],
  borderDark: gray[700],

  // 10% — accent: buttons, active states, highlights, badges
  accent: blue[5],
  accentHover: blue[6],
  accentSubtleBg: blue[0], // pill/badge backgrounds

  // text
  textPrimary: gray[900],
  textPrimaryDark: gray[100],
  textSecondary: gray[600],
  textSecondaryDark: gray[400],
  textOnAccent: gray[0],

  // semantic (reserve: pull from Primer's green/yellow/red scales when needed,
  // do not invent new hues — see decision-log.md entry #7)
  success: '#1A7F37',
  warning: '#9A6700',
  error: '#CF222E',
} as const;

// ---------------------------------------------------------------
// SPACING — 8px grid (ux-ui-guidelines.md Spacing and Symmetry Rules)
// ---------------------------------------------------------------
export const spacing = {
  xs: 4, // tight spaces only: icon gaps, small text adjustments
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
  '2xl': 40,
  '3xl': 48,
  '4xl': 64,
  '5xl': 80,
  '6xl': 96,
} as const;

// ---------------------------------------------------------------
// PADDING TOKENS — ux-ui-guidelines.md Padding Tokens table
// ---------------------------------------------------------------
export const padding = {
  control: '8px 16px', // buttons, inputs, selects, pills, badges, tabs, nav/menu items
  cell: '16px', // table cells, list rows, toasts, alerts, banners
  menu: '8px', // dropdown/menu containers, tooltips
  card: '24px', // cards, panels, containers
  modal: '32px', // modals, dialogs
  header: '0 24px', // header (height is its own token)
  pageDesktop: '32px',
  pageMobile: '16px',
} as const;

// ---------------------------------------------------------------
// RADIUS — only two values permitted
// ---------------------------------------------------------------
export const radius = {
  default: 8, // buttons, inputs, cards, containers
  prominent: 16, // modals, feature panels
} as const;

// ---------------------------------------------------------------
// SHADOW — one token, only for floating elements (menus, modals, toasts)
// ---------------------------------------------------------------
export const shadow = {
  floating: '0 4px 16px rgba(31, 35, 40, 0.12)',
} as const;

// ---------------------------------------------------------------
// TYPOGRAPHY — Manrope (headings) + Plus Jakarta Sans (body)
// ---------------------------------------------------------------
export const fontFamily = {
  heading: "'Manrope', sans-serif",
  body: "'Plus Jakarta Sans', sans-serif",
} as const;

export const fontWeight = {
  regular: 400,
  semibold: 600,
} as const;

// Max 3 sizes; a 4th only if content structure genuinely requires it.
export const fontSize = {
  sm: 14,
  md: 16,
  lg: 20,
} as const;

// ---------------------------------------------------------------
// LAYOUT SHELL
// ---------------------------------------------------------------
export const layout = {
  headerHeight: 64,
  sidebarWidth: 240,
} as const;
