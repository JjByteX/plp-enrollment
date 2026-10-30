'use server';

// features/content/actions.ts
//
// Admin actions for subjects (one at a time or from an uploaded file), rooms and the current term (step 15). Each
// checks the caller is Admin, then runs under the caller's own session so row
// level security applies and the audit log records who did it
// (decision-log.md #10). A new subject reaches the draft sections of its year
// level by a database trigger, so nothing here touches sections.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/auth/session';
import { MAX_IMPORT_ROWS } from './importSubjects';
import { UUID, parseRoomInput, parseSubjectEdit, parseSubjectInput, parseTermInput } from './schema';
import { asObject } from '@/lib/validate';

export type ContentActionResult = { ok: true; message: string } | { error: string };

const PAGE = '/admin/content';

async function isAdmin(): Promise<boolean> {
  const actor = await getCurrentUser();
  return actor?.role === 'admin';
}

type DbError = { code?: string; message: string };

// P0001 is a refusal the database wrote on purpose (for example, a subject that other subjects
// require, with their codes named), so it is shown as written. 23505 is a duplicate, 23503 a row
// still used elsewhere.
function failure(error: DbError, duplicate: string, inUse: string, fallback: string): { error: string } {
  if (error.code === 'P0001') return { error: error.message };
  if (error.code === '23505') return { error: duplicate };
  if (error.code === '23503') return { error: inUse };
  return { error: fallback };
}

const DUPLICATE_SUBJECT = 'This program already has a subject with that code.';
const SUBJECT_IN_USE = 'This subject is used by a section, a grade or a credit, so it cannot be deleted.';
const DUPLICATE_ROOM = 'A room with that name already exists.';
const ROOM_IN_USE = 'This room is used by a section, so it cannot be deleted.';

export async function addSubject(input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the subjects.' };
  const parsed = parseSubjectInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { programId, code, title, units, yearLevel, semester, hasLaboratory, offeredInSummer } = parsed.value;

  const supabase = createClient();
  const { error } = await supabase.from('subjects').insert({
    program_id: programId,
    code,
    title,
    units,
    year_level: yearLevel,
    semester,
    has_laboratory: hasLaboratory,
    offered_in_summer: offeredInSummer,
  });
  if (error) return failure(error, DUPLICATE_SUBJECT, SUBJECT_IN_USE, 'The subject could not be added.');

  revalidatePath(PAGE);
  return { ok: true, message: 'Subject added. It is in the draft sections of its year level and semester in the current term.' };
}

// Adds the subjects of an uploaded file to one program. The browser has already checked the file and
// shown the result, but nothing is trusted from it: every row is checked again with the same rules as
// Add subject. A code the program already has is skipped, not changed (an existing subject may be in
// sections, grades and prerequisites). All the new rows go in with one insert, so a file is added whole
// or not at all.
export async function importSubjects(programId: string, rows: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the subjects.' };
  if (typeof programId !== 'string' || !UUID.test(programId)) return { error: 'Choose the program.' };
  if (!Array.isArray(rows) || rows.length === 0) return { error: 'The file has no subjects.' };
  if (rows.length > MAX_IMPORT_ROWS) return { error: `Import at most ${MAX_IMPORT_ROWS} subjects at a time.` };

  const supabase = createClient();
  const { data: existingRows, error: readError } = await supabase.from('subjects').select('code').eq('program_id', programId);
  if (readError) return { error: 'The subjects could not be imported.' };
  const taken = new Set(((existingRows ?? []) as { code: string }[]).map((row) => row.code.toLowerCase()));

  const toAdd: Record<string, unknown>[] = [];
  let skipped = 0;
  for (const [index, raw] of rows.entries()) {
    const parsed = parseSubjectInput({ ...asObject(raw), programId });
    if (!parsed.ok) return { error: `Subject ${index + 1} in the file: ${parsed.reason}` };
    const { code, title, units, yearLevel, semester, hasLaboratory, offeredInSummer } = parsed.value;
    const key = code.toLowerCase();
    if (taken.has(key)) {
      skipped += 1;
      continue;
    }
    taken.add(key); // the same code twice in one file adds it once
    toAdd.push({
      program_id: programId,
      code,
      title,
      units,
      year_level: yearLevel,
      semester,
      has_laboratory: hasLaboratory,
      offered_in_summer: offeredInSummer,
    });
  }
  if (toAdd.length === 0) return { error: 'Every subject in the file is already in this program.' };

  const { error } = await supabase.from('subjects').insert(toAdd);
  if (error) {
    return failure(
      error,
      'A code in the file was just added by someone else. Choose the file again.',
      'That program was not found.',
      'The subjects could not be imported.',
    );
  }

  revalidatePath(PAGE);
  const added = `${toAdd.length} ${toAdd.length === 1 ? 'subject' : 'subjects'} added`;
  const left = skipped > 0 ? `, ${skipped} skipped because the code already exists` : '';
  return { ok: true, message: `${added}${left}. They are in the draft sections of their year level and semester in the current term.` };
}

export async function editSubject(subjectId: string, input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the subjects.' };
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { error: 'That subject was not found.' };
  const parsed = parseSubjectEdit(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { code, title, units, hasLaboratory, offeredInSummer } = parsed.value;

  const supabase = createClient();
  const { data, error } = await supabase
    .from('subjects')
    .update({ code, title, units, has_laboratory: hasLaboratory, offered_in_summer: offeredInSummer })
    .eq('id', subjectId)
    .select('id');
  if (error) return failure(error, DUPLICATE_SUBJECT, SUBJECT_IN_USE, 'The subject could not be saved.');
  if (!data || data.length === 0) return { error: 'That subject was not found.' };

  revalidatePath(PAGE);
  return { ok: true, message: 'Subject saved.' };
}

export async function deleteSubject(subjectId: string): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the subjects.' };
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { error: 'That subject was not found.' };

  const supabase = createClient();
  const { data, error } = await supabase.from('subjects').delete().eq('id', subjectId).select('id');
  if (error) return failure(error, DUPLICATE_SUBJECT, SUBJECT_IN_USE, 'The subject could not be deleted.');
  if (!data || data.length === 0) return { error: 'That subject was not found.' };

  revalidatePath(PAGE);
  return { ok: true, message: 'Subject deleted.' };
}

// roomId null adds a room; an id updates that room.
export async function saveRoom(roomId: string | null, input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the rooms.' };
  if (roomId !== null && (typeof roomId !== 'string' || !UUID.test(roomId))) return { error: 'That room was not found.' };
  const parsed = parseRoomInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { name, capacity, collegeId } = parsed.value;
  const row = { name, capacity, college_id: collegeId };

  const supabase = createClient();
  if (roomId === null) {
    const { error } = await supabase.from('rooms').insert(row);
    if (error) return failure(error, DUPLICATE_ROOM, ROOM_IN_USE, 'The room could not be added.');
    revalidatePath(PAGE);
    return { ok: true, message: 'Room added.' };
  }

  const { data, error } = await supabase.from('rooms').update(row).eq('id', roomId).select('id');
  if (error) return failure(error, DUPLICATE_ROOM, ROOM_IN_USE, 'The room could not be saved.');
  if (!data || data.length === 0) return { error: 'That room was not found.' };
  revalidatePath(PAGE);
  return { ok: true, message: 'Room saved.' };
}

export async function deleteRoom(roomId: string): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the rooms.' };
  if (typeof roomId !== 'string' || !UUID.test(roomId)) return { error: 'That room was not found.' };

  const supabase = createClient();
  const { data, error } = await supabase.from('rooms').delete().eq('id', roomId).select('id');
  if (error) return failure(error, DUPLICATE_ROOM, ROOM_IN_USE, 'The room could not be deleted.');
  if (!data || data.length === 0) return { error: 'That room was not found.' };

  revalidatePath(PAGE);
  return { ok: true, message: 'Room deleted.' };
}

// The one term row. New sections are created in this term. An issued slip, payment
// and COR keep the term they belong to, so changing the term never alters them.
export async function saveTerm(input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can set the term.' };
  const parsed = parseTermInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase
    .from('enrollment_term')
    .upsert({ id: true, school_year: parsed.value.schoolYear, semester: parsed.value.semester });
  if (error) return { error: 'The term could not be saved.' };

  // Changing the term opens the next one when the term before it was closed (step 21): the sections
  // are copied and the students who passed everything are placed, so the schedule pages change too.
  revalidatePath(PAGE);
  revalidatePath('/secretary/schedule');
  revalidatePath('/registrar/schedules');
  revalidatePath('/registrar/grades');
  return {
    ok: true,
    message:
      'Term saved. New sections are created in this term. If the term before it was closed, its sections are copied and its students are placed.',
  };
}
