'use server';

// Admin creates a staff account. No public sign-up exists.
// Order: check the caller is an Admin, invite the auth user (the invite email
// carries the set-password link), then insert the users row under the Admin's
// own session so row level security applies and the audit log records who did it.
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';
import { getCurrentUser } from '@/lib/auth/session';
import { COLLEGE_ROLES, STAFF_ROLES, type StaffRole } from '@/lib/auth/roles';
import { isEmail } from '@/lib/auth/validate';

export type CreateStaffInput = {
  fullName: string;
  email: string;
  role: string;
  collegeId: string | null;
};
export type CreateStaffResult = { ok: true; email: string } | { error: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function createStaffAccount(input: CreateStaffInput): Promise<CreateStaffResult> {
  const actor = await getCurrentUser();
  if (!actor || actor.role !== 'admin') return { error: 'Only an Admin can create accounts.' };

  const fullName = input.fullName.trim();
  const email = input.email.trim().toLowerCase();
  if (fullName.length < 2 || fullName.length > 150) return { error: 'Enter the full name.' };
  if (!isEmail(email)) return { error: 'Enter a valid email address.' };
  if (!(STAFF_ROLES as readonly string[]).includes(input.role)) return { error: 'Choose a role.' };
  const role = input.role as StaffRole;

  const needsCollege = COLLEGE_ROLES.includes(role);
  if (needsCollege && !(input.collegeId && UUID.test(input.collegeId))) {
    return { error: 'Choose the college.' };
  }
  const collegeId = needsCollege ? input.collegeId : null;

  const supabase = createClient();

  // Never invite over an existing account: a failed save below deletes the new auth user.
  const { data: existing } = await supabase.from('users').select('id').eq('email', email).maybeSingle();
  if (existing) return { error: 'An account with this email already exists.' };

  const admin = createAdminClient();
  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName },
  });
  if (inviteError || !invited.user) {
    if (inviteError?.status === 429) return { error: 'Too many emails sent. Try again later.' };
    if (inviteError?.message.toLowerCase().includes('registered')) {
      return { error: 'An account with this email already exists.' };
    }
    return { error: 'The invitation could not be sent. Nothing was created.' };
  }

  const { error: insertError } = await supabase.from('users').insert({
    auth_id: invited.user.id,
    full_name: fullName,
    email,
    role,
    college_id: collegeId,
  });
  if (insertError) {
    await admin.auth.admin.deleteUser(invited.user.id);
    return { error: 'The account could not be saved. Nothing was created.' };
  }

  return { ok: true, email };
}
