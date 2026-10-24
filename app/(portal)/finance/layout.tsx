import { requireArea } from '@/lib/auth/session';

export default async function FinanceLayout({ children }: { children: React.ReactNode }) {
  await requireArea('finance');
  return <>{children}</>;
}
