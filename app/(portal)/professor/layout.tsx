import { requireArea } from '@/lib/auth/session';

export default async function ProfessorLayout({ children }: { children: React.ReactNode }) {
  await requireArea('professor');
  return <>{children}</>;
}
