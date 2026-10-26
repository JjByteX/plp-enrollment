// features/visit-scheduling/queries.ts
//
// Reads for the Registrar's visits page. They run under the signed-in
// person's session (decision-log.md #10), so row level security applies:
// Registrar and Admin see every slot and booking, nobody else sees any.
import { createClient } from '@/lib/supabase/server';
import { hasAny } from '@/lib/supabase/rows';

export type ProgramOption = { id: string; code: string; name: string };

export type SlotStatus = 'open' | 'closed' | 'cancelled';

export type SlotBooking = {
  bookingId: string;
  applicantId: string;
  applicantRef: string;
  fullName: string;
  status: 'booked' | 'attended' | 'no_show';
};

export type SlotRow = {
  id: string;
  programId: string;
  programCode: string;
  slotDate: string; // YYYY-MM-DD
  startTime: string; // HH:MM
  endTime: string; // HH:MM
  capacity: number;
  officeName: string;
  whatToBring: string | null;
  status: SlotStatus;
  bookings: SlotBooking[];
  freeSeats: number;
};

export type UnassignedApplicant = {
  applicantId: string;
  applicantRef: string;
  fullName: string;
  admissionDate: string;
};

type RawBooking = {
  id: string;
  status: SlotBooking['status'];
  applicant_id: string;
  applicants: { applicant_ref: string; users: { full_name: string } | null } | null;
};

type RawSlot = {
  id: string;
  program_id: string;
  slot_date: string;
  start_time: string;
  end_time: string;
  capacity: number;
  office_name: string;
  what_to_bring: string | null;
  status: SlotStatus;
  programs: { code: string } | null;
  visit_bookings: RawBooking[] | null;
};

export async function listPrograms(): Promise<ProgramOption[]> {
  const supabase = createClient();
  const { data } = await supabase.from('programs').select('id, code, name').order('code');
  return (data ?? []) as ProgramOption[];
}

// Slots with who is booked in each. Optional filters: one program, one date.
// Earliest first, so the list reads in the order "Assign all" fills it.
export async function listSlots(filter: { programId?: string; date?: string } = {}): Promise<SlotRow[]> {
  const supabase = createClient();
  let query = supabase
    .from('visit_slots')
    .select(
      'id, program_id, slot_date, start_time, end_time, capacity, office_name, what_to_bring, status, ' +
        'programs(code), visit_bookings(id, status, applicant_id, applicants(applicant_ref, users(full_name)))'
    )
    .order('slot_date')
    .order('start_time')
    .order('office_name');
  if (filter.programId) query = query.eq('program_id', filter.programId);
  if (filter.date) query = query.eq('slot_date', filter.date);

  const { data } = await query;
  const rows = (data ?? []) as unknown as RawSlot[];

  return rows.map((row) => {
    const bookings: SlotBooking[] = (row.visit_bookings ?? []).map((b) => ({
      bookingId: b.id,
      applicantId: b.applicant_id,
      applicantRef: b.applicants?.applicant_ref ?? '',
      fullName: b.applicants?.users?.full_name ?? '',
      status: b.status,
    }));
    return {
      id: row.id,
      programId: row.program_id,
      programCode: row.programs?.code ?? '',
      slotDate: row.slot_date,
      startTime: row.start_time.slice(0, 5),
      endTime: row.end_time.slice(0, 5),
      capacity: row.capacity,
      officeName: row.office_name,
      whatToBring: row.what_to_bring,
      status: row.status,
      bookings,
      freeSeats: Math.max(row.capacity - bookings.length, 0),
    };
  });
}

type RawApplicant = {
  id: string;
  applicant_ref: string;
  admission_date: string;
  users: { full_name: string } | null;
  visit_bookings: unknown;
  students: unknown;
};

// Applicants of one program with no visit and not yet a student, in the order
// "Assign all unassigned" uses: admission date, then when they arrived. Someone
// who withdrew (step 17) is not listed.
export async function listUnassigned(programId: string): Promise<UnassignedApplicant[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('applicants')
    .select('id, applicant_ref, admission_date, users(full_name), visit_bookings(id), students(id)')
    .eq('program_id', programId)
    .is('withdrawn_at', null)
    .order('admission_date')
    .order('created_at')
    .order('id');
  const rows = (data ?? []) as unknown as RawApplicant[];

  return rows
    .filter((row) => !hasAny(row.visit_bookings) && !hasAny(row.students))
    .map((row) => ({
      applicantId: row.id,
      applicantRef: row.applicant_ref,
      fullName: row.users?.full_name ?? '',
      admissionDate: row.admission_date,
    }));
}
