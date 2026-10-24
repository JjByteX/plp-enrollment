import { requireArea } from '@/lib/auth/session';

export default async function StudentLayout({ children }: { children: React.ReactNode }) {
  await requireArea('student');
  return <>{children}</>;
}
