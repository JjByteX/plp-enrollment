// features/content/queries.ts
//
// Reads for the Admin content page (step 15). They run under the signed-in
// person's session (decision-log.md #10); row level security gives Admin
// every row. The subject list is read for one program at a time, which keeps
// it well under the 1000 rows a single request returns.
import { createClient } from '@/lib/supabase/server';

export type CollegeOption = { id: string; code: string; name: string };

export type SubjectRow = {
  id: string;
  code: string;
  title: string;
  units: number;
  yearLevel: number | null;
  semester: string;
  hasLaboratory: boolean;
  offeredInSummer: boolean;
};

export type RoomRow = {
  id: string;
  name: string;
  capacity: number | null;
  collegeId: string | null;
  collegeCode: string;
};

export type TermRow = { schoolYear: string; semester: string };

export async function listColleges(): Promise<CollegeOption[]> {
  const supabase = createClient();
  const { data } = await supabase.from('colleges').select('id, code, name').order('code');
  return (data ?? []) as CollegeOption[];
}

export async function listSubjects(programId: string): Promise<SubjectRow[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('subjects')
    .select('id, code, title, units, year_level, semester, has_laboratory, offered_in_summer')
    .eq('program_id', programId)
    .order('year_level', { nullsFirst: false })
    .order('code');

  return ((data ?? []) as {
    id: string;
    code: string;
    title: string;
    units: number | string;
    year_level: number | null;
    semester: string;
    has_laboratory: boolean;
    offered_in_summer: boolean;
  }[]).map((row) => ({
    id: row.id,
    code: row.code,
    title: row.title,
    units: Number(row.units),
    yearLevel: row.year_level,
    semester: row.semester,
    hasLaboratory: row.has_laboratory,
    offeredInSummer: row.offered_in_summer,
  }));
}

export async function listRooms(): Promise<RoomRow[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from('rooms')
    .select('id, name, capacity, college_id, colleges(code)')
    .order('name');

  return ((data ?? []) as unknown as {
    id: string;
    name: string;
    capacity: number | null;
    college_id: string | null;
    colleges: { code: string } | { code: string }[] | null;
  }[]).map((row) => {
    const college = Array.isArray(row.colleges) ? row.colleges[0] : row.colleges;
    return {
      id: row.id,
      name: row.name,
      capacity: row.capacity,
      collegeId: row.college_id,
      collegeCode: college?.code ?? '',
    };
  });
}

// The one term row, or null before Admin sets it (no section or COR can be made until then).
export async function getTerm(): Promise<TermRow | null> {
  const supabase = createClient();
  const { data } = await supabase.from('enrollment_term').select('school_year, semester').maybeSingle();
  const row = data as { school_year: string; semester: string } | null;
  return row ? { schoolYear: row.school_year, semester: row.semester } : null;
}
