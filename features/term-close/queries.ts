// features/term-close/queries.ts
//
// Reads for closing a term (step 21). Each calls a database function that checks the
// caller's role and scope itself (the Registrar and Admin see the term and the completed
// students; the Dean, the Secretary and Admin see the review list of their own college),
// so nobody reads more than they may.
import { createClient } from '@/lib/supabase/server';
import type { CompletedStudent, ReviewStudent, TermStatus } from './schema';

export async function getTermStatus(): Promise<TermStatus | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc('term_close_status');
  if (error || !data) return null;
  return data as TermStatus;
}

export async function listReviewStudents(): Promise<ReviewStudent[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('review_students');
  return Array.isArray(data) ? (data as ReviewStudent[]) : [];
}

export async function listCompletedStudents(): Promise<CompletedStudent[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('completed_students');
  return Array.isArray(data) ? (data as CompletedStudent[]) : [];
}
