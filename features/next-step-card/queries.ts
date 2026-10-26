// features/next-step-card/queries.ts
//
// What the persistent "Your next step" card shows. It is computed from the
// live booking, not from the latest notification, so it is never stale after
// a move. Runs under the signed-in person's session: row level security lets
// an applicant read only their own booking and the slot it points to.
//
// Applicants see their visit with the checklist for their admission type
// (step 7 decision C) and, under it, where their reschedule request stands
// (step 12): none, waiting for the Registrar, or declined with the Registrar's
// note. An approved request needs no line, the visit itself has moved. Students see their student number and any late item
// still open, their section and whether its schedule is approved (step 8), the assessment slip once issued (step 9), their payment (step 10), their COR (step 11) and whether the schedule changed after the slip (step 16). Every other role has no card (kind 'staff'); their home
// screen lists what is waiting (step 14).
//
// A person who withdrew (step 17) sees that and nothing else, whatever stage they
// had reached: the card says when, who did it and, for the Registrar, why.
import { cache } from 'react';
import { createClient } from '@/lib/supabase/server';
import type { CurrentUser } from '@/lib/auth/session';
import { formatDate, formatSlotDate, windowLabel } from '@/lib/format';
import { sectionLabel } from '@/features/section-scheduling/schema';

export type NextStep =
  | { kind: 'none' }
  | { kind: 'waiting' }
  // The applicant or student withdrew, or the Registrar withdrew them (step 17).
  | { kind: 'withdrawn'; date: string; byStaff: boolean; reason: string }
  | {
      kind: 'visit';
      date: string;
      window: string;
      office: string;
      whatToBring: string | null;
      reschedule: RescheduleState;
    }
  | {
      kind: 'student_waiting';
      studentNumber: string;
      openLateItems: string[];
      section: { label: string; approved: boolean } | null;
      slip: { paymentRequired: boolean } | null;
      payment: 'pending' | 'cleared' | null; // null when payment is not required
      cor: { schoolYear: string; semester: string } | null; // set once the student is enrolled
      scheduleChanged: boolean; // the schedule changed after the slip and the COR is not issued yet (step 16)
    }
  // Staff and Professors have no step of their own: their home screen lists what is waiting (step 14).
  | { kind: 'staff' };

// The applicant's latest reschedule request, as the card shows it.
export type RescheduleState = { status: 'none' } | { status: 'pending' } | { status: 'declined'; note: string };

type PlacementRow = {
  school_year: string;
  semester: string;
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

// Row level security lets an applicant or student read only their own row, so
// no id is needed. Null means they have not withdrawn.
async function getWithdrawnStep(): Promise<NextStep | null> {
  const supabase = createClient();
  const { data } = await supabase
    .from('applicants')
    .select('user_id, withdrawn_at, withdrawn_by, withdrawn_reason')
    .maybeSingle();
  const row = data as {
    user_id: string;
    withdrawn_at: string | null;
    withdrawn_by: string | null;
    withdrawn_reason: string | null;
  } | null;
  if (!row || !row.withdrawn_at) return null;
  return {
    kind: 'withdrawn',
    date: formatDate(row.withdrawn_at),
    byStaff: row.withdrawn_by !== row.user_id,
    reason: row.withdrawn_reason ?? '',
  };
}

async function getStudentStep(): Promise<NextStep> {
  const supabase = createClient();
  const { data } = await supabase.from('students').select('student_number').maybeSingle();
  const student = data as { student_number: string } | null;
  if (!student) return { kind: 'none' };

  const { data: late } = await supabase.rpc('my_open_late_items');

  // Row level security lets a student read only their own enrollments. A student
  // can hold one per term (step 18); the card shows the latest. The semester names
  // sort in term order ('1st', '2nd', 'summer').
  const { data: placed } = await supabase
    .from('student_sections')
    .select('school_year, semester, sections(name, year_level, schedule_status, programs(code))')
    .order('school_year', { ascending: false })
    .order('semester', { ascending: false })
    .limit(1)
    .maybeSingle();
  const placement = placed as unknown as PlacementRow | null;
  const section = placement?.sections ?? null;

  // The slip and the COR of that same term, readable by their own student (steps 9 and 11).
  let slip: { payment_required: boolean } | null = null;
  let cor: { school_year: string; semester: string } | null = null;
  if (placement) {
    const { data: slipRow } = await supabase
      .from('assessment_slips')
      .select('payment_required')
      .eq('school_year', placement.school_year)
      .eq('semester', placement.semester)
      .maybeSingle();
    slip = slipRow as { payment_required: boolean } | null;

    const { data: corRow } = await supabase
      .from('cors')
      .select('school_year, semester')
      .eq('school_year', placement.school_year)
      .eq('semester', placement.semester)
      .maybeSingle();
    cor = corRow as { school_year: string; semester: string } | null;
  }

  // A student cannot read payments, so a function answers for them (step 10).
  const { data: paymentStatus } = await supabase.rpc('my_payment_status');
  const payment = paymentStatus === 'pending' || paymentStatus === 'cleared' ? paymentStatus : null;

  // A student cannot read subjects, rooms or professors, so a function compares the slip's saved schedule (step 16).
  const { data: changed } = await supabase.rpc('my_schedule_changed');

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
    payment,
    cor: cor ? { schoolYear: cor.school_year, semester: cor.semester } : null,
    scheduleChanged: changed === true,
  };
}

// Cached for the request, so the layout and a home page that shows the person's
// progress (step 14) read it once.
export const getNextStep = cache(async (user: CurrentUser): Promise<NextStep> => {
  if (user.role !== 'student' && user.role !== 'applicant') return { kind: 'staff' };

  const withdrawn = await getWithdrawnStep();
  if (withdrawn) return withdrawn;

  if (user.role === 'student') return getStudentStep();

  const supabase = createClient();
  const { data } = await supabase
    .from('visit_bookings')
    .select('status, visit_slots(slot_date, start_time, end_time, office_name, what_to_bring)')
    .maybeSingle();
  const booking = data as unknown as BookingRow | null;

  if (!booking) return { kind: 'waiting' };
  // An attended visit means the applicant is already a student (handled above).
  // A no show has nothing to show yet.
  if (booking.status !== 'booked' || !booking.visit_slots) return { kind: 'none' };

  const slot = booking.visit_slots;

  const { data: applicant } = await supabase.from('applicants').select('admission_type').maybeSingle();
  const admissionType = (applicant as { admission_type: string } | null)?.admission_type;
  let checklist: string | null = null;
  if (admissionType) {
    const { data: text } = await supabase.rpc('document_checklist_text', { p_admission_type: admissionType });
    checklist = typeof text === 'string' ? text : null;
  }

  // Row level security lets an applicant read only the requests they sent.
  const { data: latest } = await supabase
    .from('reschedule_requests')
    .select('status, decision_note')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  const request = latest as { status: string; decision_note: string | null } | null;
  const reschedule: RescheduleState =
    request?.status === 'pending'
      ? { status: 'pending' }
      : request?.status === 'declined'
        ? { status: 'declined', note: request.decision_note ?? '' }
        : { status: 'none' };

  return {
    kind: 'visit',
    date: formatSlotDate(slot.slot_date),
    window: windowLabel(slot.start_time.slice(0, 5), slot.end_time.slice(0, 5)),
    office: slot.office_name,
    whatToBring: joinWhatToBring(checklist, slot.what_to_bring),
    reschedule,
  };
});
