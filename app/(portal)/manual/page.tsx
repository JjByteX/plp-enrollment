import { redirect } from 'next/navigation';
import { homePath } from '@/lib/auth/roles';
import { requireUser } from '@/lib/auth/session';
import { MANUAL_SOURCE } from '@/features/user-manual/content';
import { parseManual } from '@/features/user-manual/parse';
import { ManualView } from '@/features/user-manual/ManualView';

export const metadata = { title: 'User manual | PLP Enrollment' };

// The manual is written for staff. Applicants and Students follow the "Your
// next step" card instead, so they are sent back to their own home.
export default async function ManualPage() {
  const user = await requireUser();
  if (user.role === 'applicant' || user.role === 'student') redirect(homePath(user.role));

  return <ManualView manual={parseManual(MANUAL_SOURCE)} />;
}
