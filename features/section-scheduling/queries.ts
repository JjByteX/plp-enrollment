// features/section-scheduling/queries.ts
//
// Reads for the schedule pages. They run under the signed-in person's session
// (decision-log.md #10), so row level security decides what each role sees:
// the Registrar and Admin see every college, the Dean and Secretary only
// their own, a Professor only their sections, a Student only their own.
import { createClient } from '@/lib/supabase/server';
import type { CurrentUser } from '@/lib/auth/session';
import type { Meeting, ScheduleStatus } from './schema';
import { sectionLabel, subjectIsComplete } from './schema';

export type ProgramOption = { id: string; code: string; name: string; collegeId: string };

export type SectionRow = {
  id: string;
  programId: string;
  programCode: string;
  collegeId: string;
  yearLevel: number;
  name: string;
  capacity: number;
  status: ScheduleStatus;
  rejectedReason: string | null;
  subjectCount: number;
  readyCount: number; // subjects with a professor, a room and a time
  studentCount: number;
};

export type LoadingRow = {
  id: string; // section_subjects.id
  meeting: Meeting;
  code: string;
  title: string;
  units: number;
  professorId: string | null;
  professorName: string | null;
  roomId: string | null;
  roomName: string | null;
  dayOfWeek: number | null;
  startTime: string | null; // HH:MM
  endTime: string | null; // HH:MM
};

export type SectionStudent = { studentId: string; studentNumber: string; fullName: string };

export type SectionDetail = { rows: LoadingRow[]; students: SectionStudent[] };

export type PersonOption = { id: string; fullName: string };
export type RoomOption = { id: string; name: string; capacity: number | null; collegeId: string | null };

export type WaitingStudent = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  programId: string;
  programCode: string;
};

export type BoardData = {
  programs: ProgramOption[];
  sections: SectionRow[];
  professors: PersonOption[];
  rooms: RoomOption[];
  waiting: WaitingStudent[];
};

export type BoardFilter = { programId?: string; status?: ScheduleStatus };

type RawSection = {
  id: string;
  program_id: string;
  year_level: number;
  name: string;
  capacity: number;
  schedule_status: ScheduleStatus;
  rejected_reason: string | null;
  programs: { code: string; college_id: string } | null;
  section_subjects: { professor_id: string | null; room_id: string | null; day_of_week: number | null }[] | null;
  student_sections: { student_id: string }[] | null;
};

type RawLoading = {
  id: string;
  meeting: Meeting;
  professor_id: string | null;
  room_id: string | null;
  day_of_week: number | null;
  start_time: string | null;
  end_time: string | null;
  subjects: { code: string; title: string; units: number } | null;
  professor: { full_name: string } | null;
  rooms: { name: string } | null;
};

type RawStudent = {
  student_id: string;
  students: { student_number: string; applicants: { users: { full_name: string } | null } | null } | null;
};

type RawWaiting = {
  id: string;
  student_number: string;
  applicants: { program_id: string; programs: { code: string } | null; users: { full_name: string } | null } | null;
  student_sections: unknown;
};

export const STATUS_FILTERS: readonly ScheduleStatus[] = ['draft', 'pending_dean', 'dean_signed', 'approved'];

export function isScheduleStatus(value: unknown): value is ScheduleStatus {
  return typeof value === 'string' && (STATUS_FILTERS as readonly string[]).includes(value);
}

// Programs the person may create sections for: their own college, or all for
// Admin. The Registrar only reads, so every program is listed for the filter.
async function listPrograms(user: CurrentUser): Promise<ProgramOption[]> {
  const supabase = createClient();
  let query = supabase.from('programs').select('id, code, name, college_id').order('code');
  if (user.role === 'dean' || user.role === 'college_secretary') {
    if (!user.collegeId) return [];
    query = query.eq('college_id', user.collegeId);
  }
  const { data } = await query;
  return ((data ?? []) as { id: string; code: string; name: string; college_id: string }[]).map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    collegeId: row.college_id,
  }));
}

export async function listSections(filter: BoardFilter = {}): Promise<SectionRow[]> {
  const supabase = createClient();
  let query = supabase
    .from('sections')
    .select(
      'id, program_id, year_level, name, capacity, schedule_status, rejected_reason, ' +
        'programs(code, college_id), section_subjects(professor_id, room_id, day_of_week), student_sections(student_id)'
    );
  if (filter.programId) query = query.eq('program_id', filter.programId);
  if (filter.status) query = query.eq('schedule_status', filter.status);

  const { data } = await query;
  const rows = (data ?? []) as unknown as RawSection[];

  return rows
    .map((row) => {
      const subjects = (row.section_subjects ?? []).map((s) => ({
        professorId: s.professor_id,
        roomId: s.room_id,
        dayOfWeek: s.day_of_week,
      }));
      return {
        id: row.id,
        programId: row.program_id,
        programCode: row.programs?.code ?? '',
        collegeId: row.programs?.college_id ?? '',
        yearLevel: row.year_level,
        name: row.name,
        capacity: row.capacity,
        status: row.schedule_status,
        rejectedReason: row.rejected_reason,
        subjectCount: subjects.length,
        readyCount: subjects.filter(subjectIsComplete).length,
        studentCount: (row.student_sections ?? []).length,
      };
    })
    .sort((a, b) =>
      sectionLabel(a.programCode, a.yearLevel, a.name).localeCompare(sectionLabel(b.programCode, b.yearLevel, b.name))
    );
}

// The loading rows and the students of one section. Run when a section is opened.
export async function getSectionDetail(sectionId: string): Promise<SectionDetail> {
  const supabase = createClient();

  const [{ data: loading }, { data: students }] = await Promise.all([
    supabase
      .from('section_subjects')
      .select(
        'id, meeting, professor_id, room_id, day_of_week, start_time, end_time, ' +
          'subjects(code, title, units), professor:users!professor_id(full_name), rooms(name)'
      )
      .eq('section_id', sectionId),
    supabase
      .from('student_sections')
      .select('student_id, students(student_number, applicants(users(full_name)))')
      .eq('section_id', sectionId),
  ]);

  const rows = ((loading ?? []) as unknown as RawLoading[])
    .map((row) => ({
      id: row.id,
      meeting: row.meeting,
      code: row.subjects?.code ?? '',
      title: row.subjects?.title ?? '',
      units: Number(row.subjects?.units ?? 0),
      professorId: row.professor_id,
      professorName: row.professor?.full_name ?? null,
      roomId: row.room_id,
      roomName: row.rooms?.name ?? null,
      dayOfWeek: row.day_of_week,
      startTime: row.start_time ? row.start_time.slice(0, 5) : null,
      endTime: row.end_time ? row.end_time.slice(0, 5) : null,
    }))
    // lecture before laboratory
    .sort((a, b) => a.code.localeCompare(b.code) || Number(a.meeting === 'laboratory') - Number(b.meeting === 'laboratory'));

  const people = ((students ?? []) as unknown as RawStudent[])
    .map((row) => ({
      studentId: row.student_id,
      studentNumber: row.students?.student_number ?? '',
      fullName: row.students?.applicants?.users?.full_name ?? '',
    }))
    .sort((a, b) => a.studentNumber.localeCompare(b.studentNumber));

  return { rows, students: people };
}

async function listProfessors(): Promise<PersonOption[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('users')
    .select('id, full_name')
    .eq('role', 'professor')
    .eq('is_active', true)
    .order('full_name');
  return ((data ?? []) as { id: string; full_name: string }[]).map((row) => ({ id: row.id, fullName: row.full_name }));
}

async function listRooms(): Promise<RoomOption[]> {
  const supabase = createClient();
  const { data } = await supabase.from('rooms').select('id, name, capacity, college_id').order('name');
  return ((data ?? []) as { id: string; name: string; capacity: number | null; college_id: string | null }[]).map(
    (row) => ({ id: row.id, name: row.name, capacity: row.capacity, collegeId: row.college_id })
  );
}

function hasAny(value: unknown): boolean {
  return Array.isArray(value) ? value.length > 0 : value != null;
}

// Students with no section: no section existed, or every seat was taken when
// they were promoted. They are placed by themselves once a section appears or
// a capacity goes up; the Secretary or Dean can also place one by hand.
async function listWaiting(): Promise<WaitingStudent[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('students')
    .select('id, student_number, applicants(program_id, programs(code), users(full_name)), student_sections(student_id)')
    .order('student_number');
  return ((data ?? []) as unknown as RawWaiting[])
    .filter((row) => !hasAny(row.student_sections) && row.applicants)
    .map((row) => ({
      studentId: row.id,
      studentNumber: row.student_number,
      fullName: row.applicants?.users?.full_name ?? '',
      programId: row.applicants?.program_id ?? '',
      programCode: row.applicants?.programs?.code ?? '',
    }));
}

// Everything the schedule page needs, in one round of reads. The Registrar
// does not place students, so the waiting list is skipped for that role.
export async function loadBoard(user: CurrentUser, filter: BoardFilter): Promise<BoardData> {
  const collegeStaff = user.role === 'dean' || user.role === 'college_secretary' || user.role === 'admin';
  const [programs, sections, professors, rooms, waiting] = await Promise.all([
    listPrograms(user),
    listSections(filter),
    listProfessors(),
    listRooms(),
    collegeStaff ? listWaiting() : Promise.resolve([]),
  ]);
  return { programs, sections, professors, rooms, waiting };
}
