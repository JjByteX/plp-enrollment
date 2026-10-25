'use server';

// features/content/actions.ts
//
// Admin actions for subjects, rooms and the current term (step 15). Each
// checks the caller is Admin, then runs under the caller's own session so row
// level security applies and the audit log records who did it
// (decision-log.md #10). A new subject reaches the draft sections of its year
// level by a database trigger, so nothing here touches sections.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/auth/session';
import { UUID, parseRoomInput, parseSubjectEdit, parseSubjectInput, parseTermInput } from './schema';

export type ContentActionResult = { ok: true; message: string } | { error: string };

const PAGE = '/admin/content';

async function isAdmin(): Promise<boolean> {
  const actor = await getCurrentUser();
  return actor?.role === 'admin';
}

type DbError = { code?: string; message: string };

// 23505 is a duplicate, 23503 a row still used elsewhere.
function failure(error: DbError, duplicate: string, inUse: string, fallback: string): { error: string } {
  if (error.code === '23505') return { error: duplicate };
  if (error.code === '23503') return { error: inUse };
  return { error: fallback };
}

const DUPLICATE_SUBJECT = 'This program already has a subject with that code.';
const SUBJECT_IN_USE = 'This subject is already in a section, so it cannot be deleted.';
const DUPLICATE_ROOM = 'A room with that name already exists.';
const ROOM_IN_USE = 'This room is used by a section, so it cannot be deleted.';

export async function addSubject(input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the subjects.' };
  const parsed = parseSubjectInput(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { programId, code, title, units, yearLevel, hasLaboratory } = parsed.value;

  const supabase = createClient();
  const { error } = await supabase.from('subjects').insert({
    program_id: programId,
    code,
    title,
    units,
    year_level: yearLevel,
    has_laboratory: hasLaboratory,
  });
  if (error) return failure(error, DUPLICATE_SUBJECT, SUBJECT_IN_USE, 'The subject could not be added.');

  revalidatePath(PAGE);
  return { ok: true, message: 'Subject added. It is in the draft sections of its year level.' };
}

export async function editSubject(subjectId: string, input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can change the subjects.' };
  if (typeof subjectId !== 'string' || !UUID.test(subjectId)) return { error: 'That subject was not found.' };
  const parsed = parseSubjectEdit(input);
  if (!parsed.ok) return { error: parsed.reason };
  const { code, title, units, hasLaboratory } = parsed.value;

  const supabase = createClient();
  const { data, error } = await supabase
    .from('subjects')
    .update({ code, title, units, has_laboratory: hasLaboratory })
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

// The one term row. A COR keeps the term it was issued with, so changing the
// term never alters an issued COR.
export async function saveTerm(input: unknown): Promise<ContentActionResult> {
  if (!(await isAdmin())) return { error: 'Only Admin can set the term.' };
  const parsed = parseTermInput(input);
  if (!parsed.ok) return { error: parsed.reason };

  const supabase = createClient();
  const { error } = await supabase
    .from('enrollment_term')
    .upsert({ id: true, school_year: parsed.value.schoolYear, semester: parsed.value.semester });
  if (error) return { error: 'The term could not be saved.' };

  revalidatePath(PAGE);
  return { ok: true, message: 'Term saved. It applies to COR issued from now on.' };
}
