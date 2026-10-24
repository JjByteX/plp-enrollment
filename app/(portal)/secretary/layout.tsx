import { requireArea } from '@/lib/auth/session';

export default async function SecretaryLayout({ children }: { children: React.ReactNode }) {
  await requireArea('secretary');
  return <>{children}</>;
}
