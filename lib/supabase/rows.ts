// lib/supabase/rows.ts
//
// PostgREST returns an array for a one to many join and an object (or null)
// for a one to one join, so accept both when asking "is there a related row?".
export function hasAny(value: unknown): boolean {
  return Array.isArray(value) ? value.length > 0 : value != null;
}
