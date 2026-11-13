// theme.ts — the ONLY source of design tokens for this app.
// Every screen styles itself from these named tokens. No hardcoded
// colours, spacing, radii or durations in screens; if a screen needs a
// new value, add a token here first. (Pattern: mobile-kit templates/theme.ts,
// re-locked for this skeleton: Apple/Anthropic-like, clean light-first.)

export const colors = {
  light: {
    background: '#ffffff',
    surface: '#f6f6f4',
    surfaceElevated: '#ffffff',
    ink: '#0a0f1e',
    inkSecondary: '#5b6472',
    inkTertiary: '#9aa1ad',
    line: '#e6e6e2',
    accent: '#0a0f1e',
    accentInk: '#ffffff',
    danger: '#c2410c',
    stubBadgeBg: '#fef3c7',
    stubBadgeInk: '#92400e',
    liveBadgeBg: '#dcfce7',
    liveBadgeInk: '#166534',
  },
  dark: {
    background: '#0a0f1e',
    surface: '#141a2a',
    surfaceElevated: '#1c2438',
    ink: '#f2f4f8',
    inkSecondary: '#a7b0c0',
    inkTertiary: '#6b7488',
    line: '#262f45',
    accent: '#f2f4f8',
    accentInk: '#0a0f1e',
    danger: '#fb923c',
    stubBadgeBg: '#451a03',
    stubBadgeInk: '#fcd34d',
    liveBadgeBg: '#052e16',
    liveBadgeInk: '#86efac',
  },
} as const;

export type ColorScheme = keyof typeof colors;

/** Type roles — every text element uses one of these, never a raw size. */
export const type = {
  display: { fontSize: 32, lineHeight: 38, fontWeight: '700' as const },
  title: { fontSize: 22, lineHeight: 28, fontWeight: '700' as const },
  heading: { fontSize: 17, lineHeight: 24, fontWeight: '600' as const },
  body: { fontSize: 16, lineHeight: 24, fontWeight: '400' as const },
  bodyStrong: { fontSize: 16, lineHeight: 24, fontWeight: '600' as const },
  caption: { fontSize: 13, lineHeight: 18, fontWeight: '400' as const },
  captionStrong: { fontSize: 13, lineHeight: 18, fontWeight: '600' as const },
  mono: { fontSize: 13, lineHeight: 18, fontWeight: '400' as const, fontFamily: 'monospace' },
} as const;

/** Spacing scale — 4px base, up to 96px. */
export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
  xxxl: 48,
  huge: 64,
  giant: 96,
} as const;

/** Corner radii. */
export const radius = {
  sm: 2,
  md: 6,
  lg: 12,
  xl: 20,
} as const;

/** Motion durations (ms). */
export const motion = {
  fast: 120,
  base: 220,
  slow: 420,
} as const;

/** Layout. */
export const layout = {
  maxWidth: 1120,
  screenPadding: space.lg,
} as const;

export const theme = { colors, type, space, radius, motion, layout } as const;
export type Theme = typeof theme;
