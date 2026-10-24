import { requireArea } from '@/lib/auth/session';

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await requireArea('admin');
  return <>{children}</>;
}
