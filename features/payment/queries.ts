// features/payment/queries.ts
//
// Reads for the Finance payments page. They run under the signed-in person's
// session (decision-log.md #10). Finance cannot read applicants, so the list
// comes from payment_queue(), which joins name, program and section inside
// the database and refuses anyone but Finance and Admin.
import { createClient } from '@/lib/supabase/server';
import { first } from '@/features/assessment-slip/queries';

export type PaymentRow = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  programCode: string;
  section: string;
  amountDue: number | null;
  amountPaid: number;
  receiptNo: string | null;
  clearedAt: string | null;
};

export type ProgramSetting = {
  programId: string;
  code: string;
  name: string;
  paymentRequired: boolean;
};

type RawPayment = {
  student_id: string;
  student_number: string;
  full_name: string;
  program_code: string;
  section: string | null;
  amount_due: number | string | null;
  amount_paid: number | string;
  receipt_no: string | null;
  cleared_at: string | null;
};

type RawSetting = {
  program_id: string;
  payment_required: boolean;
  programs: unknown;
};

export async function listPayments(status: 'pending' | 'cleared'): Promise<PaymentRow[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('payment_queue', { p_status: status });

  return ((data ?? []) as RawPayment[]).map((row) => ({
    studentId: row.student_id,
    studentNumber: row.student_number,
    fullName: row.full_name,
    programCode: row.program_code,
    section: row.section ?? '',
    amountDue: row.amount_due === null ? null : Number(row.amount_due),
    amountPaid: Number(row.amount_paid),
    receiptNo: row.receipt_no,
    clearedAt: row.cleared_at,
  }));
}

// Every program with its payment toggle, by program code. Finance, Admin,
// Registrar and Dean may read it (row level security); only Finance and Admin
// may change it.
export async function listProgramSettings(): Promise<ProgramSetting[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('program_payment_settings')
    .select('program_id, payment_required, programs(code, name)');

  return ((data ?? []) as unknown as RawSetting[])
    .flatMap((row) => {
      const program = first<{ code: string; name: string }>(row.programs);
      return program
        ? [{ programId: row.program_id, code: program.code, name: program.name, paymentRequired: row.payment_required }]
        : [];
    })
    .sort((a, b) => a.code.localeCompare(b.code));
}
