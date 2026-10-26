// lib/validate.ts
//
// Small input checks shared by the feature schemas. No server imports, so
// client components can use it.

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type Parsed<T> = { ok: true; value: T } | { ok: false; reason: string };

export const MAX_REASON = 500;

export function asObject(raw: unknown): Record<string, unknown> | null {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw) ? (raw as Record<string, unknown>) : null;
}

// A trimmed string field, or '' when it is missing or not a string.
export function text(raw: Record<string, unknown>, key: string): string {
  const value = raw[key];
  return typeof value === 'string' ? value.trim() : '';
}

// A required reason, 1 to MAX_REASON characters after trimming.
export function parseReason(raw: unknown): Parsed<string> {
  const reason = typeof raw === 'string' ? raw.trim() : '';
  if (reason.length === 0) return { ok: false, reason: 'Enter the reason.' };
  if (reason.length > MAX_REASON) return { ok: false, reason: `The reason is longer than ${MAX_REASON} characters.` };
  return { ok: true, value: reason };
}

// The tab named in the address (?tab=...): one of the allowed names, else the fallback.
export function parseChoice<T extends string>(raw: unknown, allowed: readonly T[], fallback: T): T {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return allowed.find((item) => item === value) ?? fallback;
}

export function isRealDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

// Accepts HH:MM or HH:MM:SS (the database returns seconds) and returns HH:MM.
export function normalizeTime(value: string): string | null {
  const match = /^([01]\d|2[0-3]):([0-5]\d)(?::00)?$/.exec(value);
  return match ? `${match[1]}:${match[2]}` : null;
}

// The reason an input is not valid yet, or null when it is. Shown under a form.
export function reasonOf<T>(parsed: Parsed<T>): string | null {
  return parsed.ok ? null : parsed.reason;
}

// A Mantine NumberInput holds a number, or a string while it is empty or half
// typed. NaN lets the schema checks reject it with their own message.
export function asNumber(value: number | string): number {
  return typeof value === 'number' ? value : Number.NaN;
}

// Same, for an optional number: null when the field is empty.
export function numberOrNull(value: number | string): number | null {
  return typeof value === 'number' ? value : null;
}
