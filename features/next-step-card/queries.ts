// features/next-step-card/queries.ts
//
// What the persistent "Your next step" card shows. It is computed from the
// live booking, not from the latest notification, so it is never stale after
// a move. Runs under the signed-in person's session: row level security lets
// an applicant read only their own booking and the slot it points to.
//
// Applicants see their visit with the checklist for their admission type
// (step 7 decision C). Students see their student number and any late item
// still open, their section and whether its schedule is approved (step 8), and the assessment slip once issued (step 9). Every other role keeps "Nothing to do yet" until the
// dashboards in step 14.
import { createClient } from '@/lib/supabase/server';
import type { CurrentUser } from '@/lib/auth/session';
import { formatSlotDate, windowLabel } from '@/features/visit-scheduling/schema';
import { sectionLabel } from '@/features/section-scheduling/schema';

export type NextStep =
  | { kind: 'none' }
  | { kind: 'waiting' }
  | { kind: 'visit'; date: string; window: string; office: string; whatToBring: string | null }
  | {
      kind: 'student_waiting';
      studentNumber: string;
      openLateItems: string[];
      section: { label: string; approved: boolean } | null;
      slip: { paymentRequired: boolean } | null;
    };

type PlacementRow = {
  sections: { name: string; year_level: number; schedule_status: string; programs: { code: string } | null } | null;
};

type BookingRow = {
  status: 'booked' | 'attended' | 'no_show';
  visit_slots: {
    slot_date: string;
    start_time: string;
    end_time: string;
    office_name: string;
    what_to_bring: string | null;
  } | null;
};

// The checklist for the applicant's type, then the slot's own notes when there
// are any. Same text the visit notification carries (assign_visit_slot).
function joinWhatToBring(checklist: string | null, slotNotes: string | null): string | null {
  const notes = (slotNotes ?? '').trim();
  const list = (checklist ?? '').trim();
  if (list && notes) return `${list}\n\n${notes}`;
  return list || notes || null;
}

async function getStudentStep(): Promise<NextStep> {
  const supabase = createClient();
  const { data } = await supabase.from('students').select('student_number').maybeSingle();
  const student = data as { student_number: string } | null;
  if (!student) return { kind: 'none' };

  const { data: late } = await supabase.rpc('my_open_late_items');

  // Row level security lets a student read only their own placement and section.
  const { data: placed } = await supabase
    .from('student_sections')
    .select('sections(name, year_level, schedule_status, programs(code))')
    .maybeSingle();
  const section = (placed as unknown as PlacementRow | null)?.sections ?? null;

  // The slip is readable by its own student (step 9).
  const { data: slipRow } = await supabase.from('assessment_slips').select('payment_required').maybeSingle();
  const slip = slipRow as { payment_required: boolean } | null;

  return {
    kind: 'student_waiting',
    studentNumber: student.student_number,
    openLateItems: Array.isArray(late) ? (late as string[]) : [],
    section: section
      ? {
          label: sectionLabel(section.programs?.code ?? '', section.year_level, section.name),
          approved: section.schedule_status === 'approved',
        }
      : null,
    slip: slip ? { paymentRequired: slip.payment_required } : null,
  };
}

export async function getNextStep(user: CurrentUser): Promise<NextStep> {
  if (user.role === 'student') return getStudentStep();
  if (user.role !== 'applicant') return { kind: 'none' };

  const supabase = createClient();
  const { data } = await supabase
    .from('visit_bookings')
    .select('status, visit_slots(slot_date, start_time, end_time, office_name, what_to_bring)')
    .maybeSingle();
  const booking = data as unknown as BookingRow | null;

  if (!booking) return { kind: 'waiting' };
  // An attended visit means the applicant is already a student (handled above);
  // a no show is handled by step 12. Until then there is nothing to show.
  if (booking.status !== 'booked' || !booking.visit_slots) return { kind: 'none' };

  const slot = booking.visit_slots;

  const { data: applicant } = await supabase.from('applicants').select('admission_type').maybeSingle();
  const admissionType = (applicant as { admission_type: string } | null)?.admission_type;
  let checklist: string | null = null;
  if (admissionType) {
    const { data: text } = await supabase.rpc('document_checklist_text', { p_admission_type: admissionType });
    checklist = typeof text === 'string' ? text : null;
  }

  return {
    kind: 'visit',
    date: formatSlotDate(slot.slot_date),
    window: windowLabel(slot.start_time.slice(0, 5), slot.end_time.slice(0, 5)),
    office: slot.office_name,
    whatToBring: joinWhatToBring(checklist, slot.what_to_bring),
  };
}
