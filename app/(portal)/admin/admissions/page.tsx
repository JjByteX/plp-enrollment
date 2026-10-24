import { Stack, Title } from '@mantine/core';
import { createClient } from '@/lib/supabase/server';
import { IntakeAdmin, type IntakeRow } from '@/features/admissions-intake/IntakeAdmin';
import { spacing } from '@/styles/tokens';

export const metadata = { title: 'Admissions | PLP Enrollment' };

const LIST_LIMIT = 100;

type LogRow = {
  id: string;
  applicant_ref: string;
  full_name: string;
  program_code: string;
  source_name: string;
  status: 'accepted' | 'rejected';
  rejection_reason: string | null;
  received_at: string;
};

// Formatted here, on the server, so the browser shows the same text.
const received = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });

export default async function AdmissionsPage() {
  const supabase = createClient();
  const [{ data: settings }, { data: log }] = await Promise.all([
    supabase.from('admissions_connection_settings').select('is_enabled').eq('id', true).maybeSingle(),
    supabase
      .from('admissions_intake_log')
      .select('id, applicant_ref, full_name, program_code, source_name, status, rejection_reason, received_at')
      .order('received_at', { ascending: false })
      .limit(LIST_LIMIT),
  ]);

  const logRows = (log ?? []) as LogRow[];
  // A rejected request that was accepted later (a resend or a new send) needs no Resend button.
  const accepted = new Set(logRows.filter((row) => row.status === 'accepted').map((row) => row.applicant_ref));

  const rows: IntakeRow[] = logRows.map((row) => ({
    id: row.id,
    receivedAt: received.format(new Date(row.received_at)),
    applicantRef: row.applicant_ref,
    fullName: row.full_name,
    programCode: row.program_code,
    source: row.source_name,
    status: row.status,
    reason: row.rejection_reason,
    canResend: row.status === 'rejected' && !accepted.has(row.applicant_ref),
  }));

  return (
    <Stack gap={spacing.md}>
      <Title order={3}>Admissions</Title>
      <IntakeAdmin enabled={(settings as { is_enabled: boolean } | null)?.is_enabled ?? true} rows={rows} />
    </Stack>
  );
}
