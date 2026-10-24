// lib/auth/session.ts
//
// Who is signed in, read on the server. The role always comes from the
// users table, never from the token, so an Applicant who becomes a Student
// is treated as a Student on the next request.
import { cache } from 'react';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { canOpen, homePath, isRole, type Area, type Role } from '@/lib/auth/roles';

export type CurrentUser = {
  id: string; // users.id
  authId: string; // auth.users.id
  fullName: string;
  email: string;
  role: Role;
  collegeId: string | null;
};

type UserRow = {
  id: string;
  full_name: string;
  email: string;
  role: string;
  college_id: string | null;
};

// Null when nobody is signed in, or the signed-in account has no active
// users row. Filtering by auth_id matters: Admin can read every users row.
export const getCurrentUser = cache(async (): Promise<CurrentUser | null> => {
  const supabase = createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const authId = claimsData?.claims?.sub;
  if (!authId) return null;

  const { data } = await supabase
    .from('users')
    .select('id, full_name, email, role, college_id')
    .eq('auth_id', authId)
    .eq('is_active', true)
    .maybeSingle();

  const row = data as UserRow | null;
  if (!row || !isRole(row.role)) return null;

  return {
    id: row.id,
    authId,
    fullName: row.full_name,
    email: row.email,
    role: row.role,
    collegeId: row.college_id,
  };
});

// Signed-out visitors go to /login.
export async function requireUser(): Promise<CurrentUser> {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  return user;
}

// A role that may not open this area is sent to its own home.
export async function requireArea(area: Area): Promise<CurrentUser> {
  const user = await requireUser();
  if (!canOpen(user.role, area)) redirect(homePath(user.role));
  return user;
}
