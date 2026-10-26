// features/dashboards/queries.ts
//
// Reads for the role home screens (step 14). They run under the signed-in
// person's session (decision-log.md #10), so row level security decides what
// each count covers: the Registrar and Admin count every college, the Dean and
// Secretary only their own. Nothing here writes. A read that fails counts as 0
// and the page still opens; the pages the links lead to show the real list.
import { createClient } from '@/lib/supabase/server';
import { fetchAll } from '@/features/documents-and-numbering/queries';
import { first, listReadyStudents } from '@/features/assessment-slip/queries';
import { listReadyForCor } from '@/features/cor/queries';
import { listPayments, type PaymentRow } from '@/features/payment/queries';
import { listSections } from '@/features/section-scheduling/queries';
import {
  DAY_LABEL,
  STATUS_LABEL,
  sectionLabel,
  subjectName,
  type Meeting,
  type ScheduleStatus,
} from '@/features/section-scheduling/schema';
import { ACTION_LABEL, tableLabel, type AuditAction } from '@/features/audit-log/schema';
import { ROLE_LABEL, isRole } from '@/lib/auth/roles';
import { formatDateTime, formatShortDay, manilaToday, windowLabel } from '@/lib/format';
import type {
  ActivityItem,
  FunnelStage,
  PipelineStage,
  SectionAttention,
  VisitCapacityData,
  VisitDay,
  WorkItem,
} from './schema';

async function headCount(query: PromiseLike<{ count: number | null }>): Promise<number> {
  const { count } = await query;
  return count ?? 0;
}

async function sectionsWithStatus(status: string): Promise<number> {
  const supabase = createClient();
  return headCount(
    supabase.from('sections').select('id', { count: 'exact', head: true }).eq('schedule_status', status)
  );
}

type RawApplicant = { id: string; visit_bookings: unknown; students: unknown };
type RawBooking = { visit_slots: { slot_date: string } | { slot_date: string }[] | null };

type ApplicantCounts = { unassigned: number; atDocuments: number };

// Applicants who are not students yet: those with no visit, and those whose
// visit date has come (today or earlier), who wait for the Registrar to
// receive their documents. Someone who withdrew (step 17) is not counted.
async function applicantCounts(): Promise<ApplicantCounts> {
  const supabase = createClient();
  const today = manilaToday();
  const rows = await fetchAll<RawApplicant>((from, to) =>
    supabase
      .from('applicants')
      .select('id, visit_bookings(visit_slots(slot_date)), students(id)')
      .is('withdrawn_at', null)
      .order('id')
      .range(from, to)
  );

  let unassigned = 0;
  let atDocuments = 0;
  for (const row of rows) {
    if (first(row.students) !== null) continue;
    const booking = first<RawBooking>(row.visit_bookings);
    if (!booking) {
      unassigned += 1;
    } else if ((first<{ slot_date: string }>(booking.visit_slots)?.slot_date ?? '9999-12-31') <= today) {
      atDocuments += 1;
    }
  }
  return { unassigned, atDocuments };
}

async function pendingRequests(): Promise<number> {
  const supabase = createClient();
  return headCount(
    supabase.from('reschedule_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending')
  );
}

// The Registrar's pages, with what waits on each. Also used by Admin.
async function registrarItems(applicants: ApplicantCounts): Promise<WorkItem[]> {
  const [requests, schedules, slips, cors] = await Promise.all([
    pendingRequests(),
    sectionsWithStatus('dean_signed'),
    listReadyStudents(),
    listReadyForCor(),
  ]);
  return [
    { href: '/registrar/visits', label: 'Visits', icon: 'visits', waiting: applicants.unassigned },
    { href: '/registrar/reschedules', label: 'Reschedules', icon: 'reschedules', waiting: requests },
    { href: '/registrar/documents', label: 'Documents', icon: 'documents', waiting: applicants.atDocuments },
    { href: '/registrar/schedules', label: 'Schedules', icon: 'schedules', waiting: schedules },
    { href: '/registrar/slips', label: 'Slips', icon: 'slips', waiting: slips.length },
    { href: '/registrar/cors', label: 'COR', icon: 'cor', waiting: cors.length },
  ];
}

// ---------------------------------------------------------------
// Visit capacity: the next days with an open slot, and whether the open
// seats cover the applicants who still have no visit date.
// ---------------------------------------------------------------
const CAPACITY_DAYS = 7;

type RawCapacitySlot = { slot_date: string; capacity: number; visit_bookings: { id: string }[] | null };

async function visitCapacity(applicants: ApplicantCounts): Promise<VisitCapacityData> {
  const supabase = createClient();
  const today = manilaToday();
  const slots = await fetchAll<RawCapacitySlot>((from, to) =>
    supabase
      .from('visit_slots')
      .select('slot_date, capacity, visit_bookings(id)')
      .eq('status', 'open')
      .gte('slot_date', today)
      .order('slot_date')
      .range(from, to)
  );

  const byDate = new Map<string, { booked: number; capacity: number }>();
  let freeSeats = 0;
  for (const slot of slots) {
    const booked = (slot.visit_bookings ?? []).length;
    freeSeats += Math.max(slot.capacity - booked, 0);
    const day = byDate.get(slot.slot_date) ?? { booked: 0, capacity: 0 };
    byDate.set(slot.slot_date, { booked: day.booked + booked, capacity: day.capacity + slot.capacity });
  }

  const days: VisitDay[] = Array.from(byDate.entries())
    .slice(0, CAPACITY_DAYS)
    .map(([date, day]) => ({ date, label: formatShortDay(date), booked: day.booked, capacity: day.capacity }));

  return { days, freeSeats, unassigned: applicants.unassigned };
}

export async function getRegistrarHome(): Promise<{ items: WorkItem[]; capacity: VisitCapacityData }> {
  const applicants = await applicantCounts();
  const [items, capacity] = await Promise.all([registrarItems(applicants), visitCapacity(applicants)]);
  return { items, capacity };
}

// ---------------------------------------------------------------
// Schedule pipeline for the Registrar and Admin: sections at each step of
// the approval chain, across every college.
// ---------------------------------------------------------------
const PIPELINE_STATUSES: ScheduleStatus[] = ['draft', 'pending_dean', 'dean_signed', 'approved'];

export async function getPipeline(): Promise<PipelineStage[]> {
  const counts = await Promise.all(PIPELINE_STATUSES.map(sectionsWithStatus));
  return PIPELINE_STATUSES.map((status, index) => ({ status, label: STATUS_LABEL[status], count: counts[index] }));
}

// ---------------------------------------------------------------
// Finance: who waits for a payment to be recorded, and what came in.
// ---------------------------------------------------------------
const FINANCE_PREVIEW = 5;

export type FinanceHome = {
  items: WorkItem[];
  pending: PaymentRow[]; // the first few waiting, lowest student number first
  recent: PaymentRow[]; // the latest cleared payments
  clearedCount: number;
  collected: number; // pesos paid across every cleared payment
};

export async function getFinanceHome(): Promise<FinanceHome> {
  const [pending, cleared] = await Promise.all([listPayments('pending'), listPayments('cleared')]);
  const newestFirst = [...cleared].sort((a, b) => (b.clearedAt ?? '').localeCompare(a.clearedAt ?? ''));
  return {
    items: [{ href: '/finance/payments', label: 'Payments', icon: 'payments', waiting: pending.length }],
    pending: pending.slice(0, FINANCE_PREVIEW),
    recent: newestFirst.slice(0, FINANCE_PREVIEW),
    clearedCount: cleared.length,
    collected: cleared.reduce((sum, row) => sum + row.amountPaid, 0),
  };
}

// ---------------------------------------------------------------
// Dean and Secretary: the sections that wait on this person, the seats
// across their college, and the students still without a section. Row level
// security limits every read to the person's own college.
// ---------------------------------------------------------------
const ATTENTION_LIMIT = 5;
const FILL_LIMIT = 6;

type RawWaitingStudent = { id: string; student_sections: unknown };

// A student who withdrew (step 17) is not waiting for a seat.
async function studentsWithoutSection(): Promise<number> {
  const supabase = createClient();
  const rows = await fetchAll<RawWaitingStudent>((from, to) =>
    supabase
      .from('students')
      .select('id, student_sections(student_id), applicants!inner(withdrawn_at)')
      .is('applicants.withdrawn_at', null)
      .order('id')
      .range(from, to)
  );
  return rows.filter((row) => first(row.student_sections) === null).length;
}

export type SeatRow = { id: string; label: string; filled: number; capacity: number };

export type CollegeHome = {
  items: WorkItem[];
  pipeline: PipelineStage[];
  attention: SectionAttention[];
  attentionTotal: number;
  seats: SeatRow[];
};

// The Dean signs off what the Secretary submitted; the Secretary works on drafts.
export async function getCollegeHome(role: 'dean' | 'secretary'): Promise<CollegeHome> {
  const mine: ScheduleStatus = role === 'dean' ? 'pending_dean' : 'draft';
  const [sections, waiting] = await Promise.all([listSections(), studentsWithoutSection()]);

  const label = (section: (typeof sections)[number]) => sectionLabel(section.programCode, section.yearLevel, section.name);
  const queue = sections.filter((section) => section.status === mine);

  return {
    items: [
      { href: '/secretary/schedule', label: 'Schedules', icon: 'schedules', waiting: queue.length },
      { href: '/secretary/schedule', label: 'Waiting for a section', icon: 'schedules', waiting },
    ],
    pipeline: PIPELINE_STATUSES.map((status) => ({
      status,
      label: STATUS_LABEL[status],
      count: sections.filter((section) => section.status === status).length,
    })),
    attention: queue.slice(0, ATTENTION_LIMIT).map((section) => ({
      id: section.id,
      label: label(section),
      detail: [
        `${section.readyCount} of ${section.subjectCount} subjects ready`,
        `${section.studentCount} students`,
        section.status === 'draft' && section.rejectedReason ? `Sent back: ${section.rejectedReason}` : '',
      ]
        .filter(Boolean)
        .join(', '),
    })),
    attentionTotal: queue.length,
    seats: sections
      .filter((section) => section.capacity > 0)
      .map((section) => ({ id: section.id, label: label(section), filled: section.studentCount, capacity: section.capacity }))
      .sort((a, b) => b.filled / b.capacity - a.filled / a.capacity)
      .slice(0, FILL_LIMIT),
  };
}

type RawIntake = { applicant_ref: string; status: string };

// Rejected Admissions requests that were not accepted later: the ones the
// Resend button still applies to (same rule as the Admissions page, which
// reads the latest 100).
async function failedIntakes(): Promise<number> {
  const supabase = createClient();
  const { data } = await supabase
    .from('admissions_intake_log')
    .select('applicant_ref, status')
    .order('received_at', { ascending: false })
    .limit(100);
  const rows = (data ?? []) as RawIntake[];
  const accepted = new Set(rows.filter((row) => row.status === 'accepted').map((row) => row.applicant_ref));
  return rows.filter((row) => row.status === 'rejected' && !accepted.has(row.applicant_ref)).length;
}

const ACTIVITY_LIMIT = 6;

type RawActivity = {
  id: number;
  actor_id: string | null;
  actor_role: string | null;
  action: string;
  table_name: string;
  created_at: string;
};

// The newest changes in the audit log. Only Admin can read it (row level
// security), so anyone else gets an empty list.
async function recentActivity(): Promise<ActivityItem[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('audit_log')
    .select('id, actor_id, actor_role, action, table_name, created_at')
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(ACTIVITY_LIMIT);
  const rows = (data ?? []) as unknown as RawActivity[];

  const actorIds = Array.from(new Set(rows.flatMap((row) => (row.actor_id ? [row.actor_id] : []))));
  const names = new Map<string, string>();
  if (actorIds.length > 0) {
    const { data: users } = await supabase.from('users').select('id, full_name').in('id', actorIds);
    for (const user of (users ?? []) as { id: string; full_name: string }[]) names.set(user.id, user.full_name);
  }

  return rows.map((row) => {
    const name = row.actor_id ? (names.get(row.actor_id) ?? 'Unknown account') : 'System';
    const role = row.actor_role && isRole(row.actor_role) ? ROLE_LABEL[row.actor_role] : row.actor_role;
    return {
      id: String(row.id),
      when: formatDateTime(row.created_at),
      actor: role ? `${name} (${role})` : name,
      text: `${ACTION_LABEL[row.action as AuditAction] ?? row.action} in ${tableLabel(row.table_name)}`,
    };
  });
}

export async function getAdminHome(): Promise<{
  items: WorkItem[];
  capacity: VisitCapacityData;
  activity: ActivityItem[];
}> {
  const applicants = await applicantCounts();
  const [failed, registrar, pending, capacity, activity] = await Promise.all([
    failedIntakes(),
    registrarItems(applicants),
    listPayments('pending'),
    visitCapacity(applicants),
    recentActivity(),
  ]);
  return {
    items: [
      { href: '/admin/accounts', label: 'Accounts', icon: 'accounts', waiting: null },
      { href: '/admin/content', label: 'Content', icon: 'content', waiting: null },
      { href: '/admin/admissions', label: 'Admissions', icon: 'admissions', waiting: failed },
      ...registrar,
      { href: '/finance/payments', label: 'Payments', icon: 'payments', waiting: pending.length },
      { href: '/admin/audit', label: 'Audit log', icon: 'audit', waiting: null },
    ],
    capacity,
    activity,
  };
}

// How far this year's applicants have come, from the live tables. Each stage
// counts people who reached it, so a stage never exceeds the one before it.
// Someone who withdrew (step 17) is left out of every stage, so the funnel shows
// who is still in the process.
export async function getFunnel(): Promise<FunnelStage[]> {
  const supabase = createClient();
  const [admitted, received, placed, slips, enrolled] = await Promise.all([
    headCount(supabase.from('applicants').select('id', { count: 'exact', head: true }).is('withdrawn_at', null)),
    headCount(
      supabase
        .from('students')
        .select('id, applicants!inner(withdrawn_at)', { count: 'exact', head: true })
        .is('applicants.withdrawn_at', null)
    ),
    headCount(supabase.from('student_sections').select('student_id', { count: 'exact', head: true })),
    headCount(
      supabase
        .from('assessment_slips')
        .select('id, students!inner(applicants!inner(withdrawn_at))', { count: 'exact', head: true })
        .is('students.applicants.withdrawn_at', null)
    ),
    headCount(
      supabase
        .from('cors')
        .select('id, students!inner(applicants!inner(withdrawn_at))', { count: 'exact', head: true })
        .is('students.applicants.withdrawn_at', null)
    ),
  ]);
  return [
    { label: 'Admitted', count: admitted },
    { label: 'Documents received', count: received },
    { label: 'Placed in a section', count: placed },
    { label: 'Assessment slip issued', count: slips },
    { label: 'Enrolled', count: enrolled },
  ];
}

export type LoadRow = {
  id: string;
  sectionId: string;
  subjectCode: string;
  subject: string; // "COMP 104 Lab"
  title: string;
  section: string;
  schedule: string;
  room: string;
  day: number | null; // 1 Monday to 7 Sunday
  start: string; // HH:MM, empty when the subject has no time yet
  end: string;
};

export type ClassStudent = { sectionId: string; subjectCode: string; studentNumber: string; fullName: string };

type RawLoad = {
  id: string;
  meeting: Meeting;
  section_id: string;
  day_of_week: number | null;
  start_time: string | null;
  end_time: string | null;
  subjects: { code: string; title: string } | null;
  sections: { name: string; year_level: number; schedule_status: string; programs: { code: string } | null } | null;
  rooms: { name: string } | null;
};

type RawClass = { section_id: string; subject_code: string; student_number: string; full_name: string };

// The signed-in Professor's own subjects in approved schedules, and the class
// lists for them (name and student number only, through the
// professor_class_lists view). Row level security limits both to this person.
export async function getProfessorLoad(): Promise<{ rows: LoadRow[]; students: ClassStudent[] }> {
  const supabase = createClient();
  const [{ data: load }, { data: classes }] = await Promise.all([
    supabase
      .from('section_subjects')
      .select(
        'id, meeting, section_id, day_of_week, start_time, end_time, subjects(code, title), ' +
          'sections(name, year_level, schedule_status, programs(code)), rooms(name)'
      ),
    supabase.from('professor_class_lists').select('section_id, subject_code, student_number, full_name'),
  ]);

  const rows = ((load ?? []) as unknown as RawLoad[])
    .filter((row) => row.sections?.schedule_status === 'approved' && row.subjects)
    .map((row) => ({
      sort: `${row.day_of_week ?? 9}${(row.start_time ?? '').slice(0, 5)}`,
      row: {
        id: row.id,
        sectionId: row.section_id,
        subjectCode: row.subjects?.code ?? '',
        subject: subjectName(row.subjects?.code ?? '', row.meeting),
        title: row.subjects?.title ?? '',
        section: sectionLabel(row.sections?.programs?.code ?? '', row.sections?.year_level ?? 0, row.sections?.name ?? ''),
        schedule:
          row.day_of_week && row.start_time && row.end_time
            ? `${DAY_LABEL[row.day_of_week] ?? ''} ${windowLabel(row.start_time.slice(0, 5), row.end_time.slice(0, 5))}`
            : '',
        room: row.rooms?.name ?? '',
        day: row.day_of_week,
        start: row.start_time ? row.start_time.slice(0, 5) : '',
        end: row.end_time ? row.end_time.slice(0, 5) : '',
      },
    }))
    .sort((a, b) => a.sort.localeCompare(b.sort))
    .map((entry) => entry.row);

  const students = ((classes ?? []) as unknown as RawClass[])
    .map((row) => ({
      sectionId: row.section_id,
      subjectCode: row.subject_code,
      studentNumber: row.student_number,
      fullName: row.full_name,
    }))
    .sort((a, b) => a.studentNumber.localeCompare(b.studentNumber));

  return { rows, students };
}
