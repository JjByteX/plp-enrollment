// features/audit-log/queries.ts
//
// Reads for the Admin audit log page. They run under the signed-in person's
// session (decision-log.md #10), so row level security applies: only Admin
// can read audit_log (policy admin_read), nobody else gets a row. Nothing here
// writes; the table is append only.
import { createClient } from '@/lib/supabase/server';
import { PAGE_SIZE, type AuditFilters } from './schema';

export type AuditEntry = {
  id: string;
  createdAt: string; // ISO timestamp
  actorName: string; // "System" when the database acted with nobody signed in
  actorRole: string | null;
  action: string;
  table: string;
  recordId: string | null;
  reason: string | null;
  oldData: Record<string, unknown> | null;
  newData: Record<string, unknown> | null;
};

export type AuditPage = { entries: AuditEntry[]; total: number };

type RawEntry = {
  id: number;
  actor_id: string | null;
  actor_role: string | null;
  action: string;
  table_name: string;
  record_id: string | null;
  old_data: Record<string, unknown> | null;
  new_data: Record<string, unknown> | null;
  reason: string | null;
  created_at: string;
};

// One page of the log, newest first. The id breaks ties so two changes made in
// the same instant keep a steady order between pages.
export async function listAuditEntries(filters: AuditFilters): Promise<AuditPage> {
  const supabase = createClient();
  const from = (filters.page - 1) * PAGE_SIZE;

  let query = supabase
    .from('audit_log')
    .select('id, actor_id, actor_role, action, table_name, record_id, old_data, new_data, reason, created_at', {
      count: 'exact',
    })
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .range(from, from + PAGE_SIZE - 1);
  if (filters.table) query = query.eq('table_name', filters.table);
  if (filters.action) query = query.eq('action', filters.action);

  const { data, count } = await query;
  const rows = (data ?? []) as unknown as RawEntry[];

  // audit_log keeps actor_id without a foreign key (the row must outlive the
  // account), so names are looked up in one extra read.
  const actorIds = Array.from(new Set(rows.flatMap((row) => (row.actor_id ? [row.actor_id] : []))));
  const names = new Map<string, string>();
  if (actorIds.length > 0) {
    const { data: users } = await supabase.from('users').select('id, full_name').in('id', actorIds);
    for (const user of (users ?? []) as { id: string; full_name: string }[]) names.set(user.id, user.full_name);
  }

  return {
    total: count ?? 0,
    entries: rows.map((row) => ({
      id: String(row.id),
      createdAt: row.created_at,
      actorName: row.actor_id ? (names.get(row.actor_id) ?? 'Unknown account') : 'System',
      actorRole: row.actor_role,
      action: row.action,
      table: row.table_name,
      recordId: row.record_id,
      reason: row.reason,
      oldData: row.old_data,
      newData: row.new_data,
    })),
  };
}
