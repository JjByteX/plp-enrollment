import { requireArea } from '@/lib/auth/session';

export default async function RegistrarLayout({ children }: { children: React.ReactNode }) {
  await requireArea('registrar');
  return <>{children}</>;
}
