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
import { listPayments } from '@/features/payment/queries';
import { DAY_LABEL, sectionLabel, subjectName, windowLabel, type Meeting } from '@/features/section-scheduling/schema';
import { manilaToday } from '@/features/visit-scheduling/schema';
import type { FunnelStage, WorkItem } from './schema';

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

// Applicants who are not students yet: those with no visit, and those whose
// visit date has come (today or earlier), who wait for the Registrar to
// receive their documents.
async function applicantCounts(): Promise<{ unassigned: number; atDocuments: number }> {
  const supabase = createClient();
  const today = manilaToday();
  const rows = await fetchAll<RawApplicant>((from, to) =>
    supabase
      .from('applicants')
      .select('id, visit_bookings(visit_slots(slot_date)), students(id)')
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
async function registrarItems(): Promise<WorkItem[]> {
  const [applicants, requests, schedules, slips, cors] = await Promise.all([
    applicantCounts(),
    pendingRequests(),
    sectionsWithStatus('dean_signed'),
    listReadyStudents(),
    listReadyForCor(),
  ]);
  return [
    { href: '/registrar/visits', label: 'Visits', waiting: applicants.unassigned },
    { href: '/registrar/reschedules', label: 'Reschedules', waiting: requests },
    { href: '/registrar/documents', label: 'Documents', waiting: applicants.atDocuments },
    { href: '/registrar/schedules', label: 'Schedules', waiting: schedules },
    { href: '/registrar/slips', label: 'Slips', waiting: slips.length },
    { href: '/registrar/cors', label: 'COR', waiting: cors.length },
  ];
}

export async function getRegistrarItems(): Promise<WorkItem[]> {
  return registrarItems();
}

export async function getFinanceItems(): Promise<WorkItem[]> {
  const pending = await listPayments('pending');
  return [{ href: '/finance/payments', label: 'Payments', waiting: pending.length }];
}

// The Dean signs off what the Secretary submitted; the Secretary works on drafts.
export async function getCollegeItems(role: 'dean' | 'secretary'): Promise<WorkItem[]> {
  const waiting = await sectionsWithStatus(role === 'dean' ? 'pending_dean' : 'draft');
  return [{ href: '/secretary/schedule', label: 'Schedules', waiting }];
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

export async function getAdminItems(): Promise<WorkItem[]> {
  const [failed, registrar, pending] = await Promise.all([failedIntakes(), registrarItems(), listPayments('pending')]);
  return [
    { href: '/admin/accounts', label: 'Accounts', waiting: null },
    { href: '/admin/content', label: 'Content', waiting: null },
    { href: '/admin/admissions', label: 'Admissions', waiting: failed },
    ...registrar,
    { href: '/finance/payments', label: 'Payments', waiting: pending.length },
    { href: '/admin/audit', label: 'Audit log', waiting: null },
  ];
}

// How far this year's applicants have come, from the live tables. Each stage
// counts people who reached it, so a stage never exceeds the one before it.
export async function getFunnel(): Promise<FunnelStage[]> {
  const supabase = createClient();
  const count = (table: string) =>
    headCount(supabase.from(table).select('id', { count: 'exact', head: true }));
  const [admitted, received, placed, slips, enrolled] = await Promise.all([
    count('applicants'),
    count('students'),
    headCount(supabase.from('student_sections').select('student_id', { count: 'exact', head: true })),
    count('assessment_slips'),
    count('cors'),
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
