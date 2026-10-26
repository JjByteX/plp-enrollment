// features/audit-log/schema.ts
//
// What the Admin audit log page shows (step 13). The log is written by the
// database (log_audit trigger) and is append only; this page only reads it.
// This file holds the filter values, labels and small helpers. No server
// imports, so client components can use it.

export const PAGE_SIZE = 50;

export const AUDIT_ACTIONS = ['INSERT', 'UPDATE', 'DELETE'] as const;
export type AuditAction = (typeof AUDIT_ACTIONS)[number];

export const ACTION_LABEL: Record<AuditAction, string> = {
  INSERT: 'Created',
  UPDATE: 'Changed',
  DELETE: 'Deleted',
};

// Every table with the log_audit trigger: the init migration's list, plus
// document_requirements (step 7) and enrollment_term (step 11). A table added
// later with the trigger needs one line here to appear in the filter.
export const AUDIT_TABLE_LABEL: Record<string, string> = {
  applicants: 'Applicants',
  assessment_slips: 'Assessment slips',
  admissions_connection_settings: 'Admissions connection',
  colleges: 'Colleges',
  cors: 'COR',
  document_requirements: 'Document requirements',
  documents: 'Documents',
  enrollment_term: 'Enrollment term',
  mass_reschedules: 'Mass reschedules',
  payments: 'Payments',
  program_payment_settings: 'Payment settings',
  programs: 'Programs',
  reschedule_requests: 'Reschedule requests',
  rooms: 'Rooms',
  section_subjects: 'Section subjects',
  sections: 'Sections',
  student_sections: 'Student sections',
  students: 'Students',
  subjects: 'Subjects',
  users: 'Accounts',
  visit_bookings: 'Visit bookings',
  visit_slots: 'Visit slots',
};

export function tableLabel(table: string): string {
  return AUDIT_TABLE_LABEL[table] ?? table;
}

export type AuditFilters = {
  table: string | null;
  action: AuditAction | null;
  page: number; // 1-based
};

// Reads the URL's search params. A value that is not on the lists is ignored,
// so a typed-in URL can never reach the query.
export function parseAuditFilters(raw: { table?: string; action?: string; page?: string }): AuditFilters {
  const table = raw.table && raw.table in AUDIT_TABLE_LABEL ? raw.table : null;
  const action = (AUDIT_ACTIONS as readonly string[]).includes(raw.action ?? '') ? (raw.action as AuditAction) : null;
  const parsed = Number.parseInt(raw.page ?? '', 10);
  const page = Number.isInteger(parsed) && parsed >= 1 ? parsed : 1;
  return { table, action, page };
}

// The query string for a set of filters. Defaults are left out, so the plain
// page has a plain URL.
export function auditHref(filters: AuditFilters): string {
  const params = new URLSearchParams();
  if (filters.table) params.set('table', filters.table);
  if (filters.action) params.set('action', filters.action);
  if (filters.page > 1) params.set('page', String(filters.page));
  const query = params.toString();
  return query ? `/admin/audit?${query}` : '/admin/audit';
}

export type FieldChange = { field: string; before: string; after: string };

function show(value: unknown): string {
  if (value === undefined || value === null) return 'empty';
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

// The fields that differ between the old and new row. An insert lists every
// field with a value, a delete lists every field it had, an update lists only
// the fields that changed.
export function changedFields(
  oldData: Record<string, unknown> | null,
  newData: Record<string, unknown> | null
): FieldChange[] {
  const before = oldData ?? {};
  const after = newData ?? {};
  const fields = Array.from(new Set([...Object.keys(before), ...Object.keys(after)])).sort((a, b) => a.localeCompare(b));
  return fields
    .filter((field) => JSON.stringify(before[field]) !== JSON.stringify(after[field]))
    .map((field) => ({ field, before: show(before[field]), after: show(after[field]) }));
}
