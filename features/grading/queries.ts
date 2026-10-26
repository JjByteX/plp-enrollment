// features/grading/queries.ts
//
// Reads for the grading pages (step 19). Each calls a database function that
// checks the caller's role and scope itself (Professor: own subjects, Dean:
// own college, Registrar and Admin: all), so nobody reads more than they may.
import { createClient } from '@/lib/supabase/server';
import { UUID, parseGradeTab, scaleReady, type GradeChange, type GradeSection, type Scale, type Sheet } from './schema';

const EMPTY_SCALE: Scale = { incWindowDays: 14, bands: [] };

export async function getScale(): Promise<Scale> {
  const supabase = createClient();
  const { data } = await supabase.rpc('grading_scale');
  const scale = data as Scale | null;
  return scale && Array.isArray(scale.bands) ? scale : EMPTY_SCALE;
}

// An approved incomplete grade past its window turns into a failed 5.0. Run before the
// Dean's or the Registrar's page reads, so the page never shows a stale incomplete.
export async function lapseIncompleteGrades(): Promise<void> {
  const supabase = createClient();
  await supabase.rpc('lapse_incomplete_grades');
}

export async function listGradeSections(): Promise<GradeSection[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('grade_sections');
  return Array.isArray(data) ? (data as GradeSection[]) : [];
}

export async function getSheet(sectionId: string, subjectId: string): Promise<Sheet | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc('grade_sheet', { p_section: sectionId, p_subject: subjectId });
  if (error || !data) return null;
  return data as Sheet;
}

export async function listGradeChanges(): Promise<GradeChange[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('grade_changes_list');
  return Array.isArray(data) ? (data as GradeChange[]) : [];
}

// Everything a Grades page needs, read in one place so the three pages stay the same.
// The Dean's and the Registrar's pages catch up lapsed incompletes first.
export async function loadGradesPage(
  searchParams: { tab?: string | string[]; section?: string | string[]; subject?: string | string[] },
  options: { lapse: boolean },
) {
  if (options.lapse) await lapseIncompleteGrades();
  const tab = parseGradeTab(searchParams.tab);
  const sectionId = Array.isArray(searchParams.section) ? searchParams.section[0] : searchParams.section;
  const subjectId = Array.isArray(searchParams.subject) ? searchParams.subject[0] : searchParams.subject;
  const wanted = sectionId && subjectId && UUID.test(sectionId) && UUID.test(subjectId);

  const [scale, sections, changes, sheet] = await Promise.all([
    getScale(),
    listGradeSections(),
    tab === 'changes' ? listGradeChanges() : Promise.resolve([] as GradeChange[]),
    wanted ? getSheet(sectionId, subjectId) : Promise.resolve(null),
  ]);
  return { tab, ready: scaleReady(scale), sections, changes, sheet };
}
