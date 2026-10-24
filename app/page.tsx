import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/lib/auth/session';
import { homePath } from '@/lib/auth/roles';

// Signed in goes to the role's own area, otherwise to sign in.
export default async function HomePage() {
  const user = await getCurrentUser();
  redirect(user ? homePath(user.role) : '/login');
}
