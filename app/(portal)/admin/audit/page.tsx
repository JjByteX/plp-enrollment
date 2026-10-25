import { AuditLogView, type AuditRow } from '@/features/audit-log/AuditLogView';
import { listAuditEntries } from '@/features/audit-log/queries';
import { parseAuditFilters } from '@/features/audit-log/schema';

export const metadata = { title: 'Audit log | PLP Enrollment' };

// Formatted here, on the server, so the browser shows the same text.
const when = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });

// Admin only: the admin layout checks the role, and row level security on
// audit_log lets only Admin read it. Filters and the page number are in the URL.
export default async function AuditPage({
  searchParams,
}: {
  searchParams: { table?: string; action?: string; page?: string };
}) {
  const filters = parseAuditFilters(searchParams);
  const { entries, total } = await listAuditEntries(filters);
  const rows: AuditRow[] = entries.map((entry) => ({ ...entry, when: when.format(new Date(entry.createdAt)) }));

  return <AuditLogView rows={rows} total={total} filters={filters} />;
}
