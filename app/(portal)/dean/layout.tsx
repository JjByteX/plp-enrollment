import { requireArea } from '@/lib/auth/session';

export default async function DeanLayout({ children }: { children: React.ReactNode }) {
  await requireArea('dean');
  return <>{children}</>;
}
