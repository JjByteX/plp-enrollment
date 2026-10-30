import { createClient } from '@/lib/supabase/server';
import { fetchAll } from '@/features/documents-and-numbering/queries';
import type { AccountRow } from './AccountsList';
import { AccountsView } from './AccountsView';

export const metadata = { title: 'Accounts | PLP Enrollment' };

type RawAccount = {
  id: string;
  full_name: string;
  email: string;
  role: string;
  college_id: string | null;
  is_active: boolean;
  created_at: string;
};

// Admin only: the admin layout checks the role, and row level security on
// users lets Admin read every account.
export default async function AccountsPage() {
  const supabase = createClient();
  const [collegesResult, users] = await Promise.all([
    supabase.from('colleges').select('id, name').order('name'),
    // Read in pages of 1000, so a long list of applicants and students is not cut off.
    fetchAll<RawAccount>((from, to) =>
      supabase
        .from('users')
        .select('id, full_name, email, role, college_id, is_active, created_at')
        .order('created_at', { ascending: false })
        .order('id')
        .range(from, to),
    ),
  ]);

  const collegeRows = (collegesResult.data ?? []) as { id: string; name: string }[];
  const colleges = collegeRows.map((college) => ({ value: college.id, label: college.name }));
  const collegeName = new Map(collegeRows.map((college) => [college.id, college.name]));

  const accounts: AccountRow[] = users.map((user) => ({
    id: user.id,
    fullName: user.full_name,
    email: user.email,
    role: user.role,
    college: user.college_id ? collegeName.get(user.college_id) ?? null : null,
    isActive: user.is_active,
    createdAt: user.created_at,
  }));

  return <AccountsView colleges={colleges} accounts={accounts} />;
}
