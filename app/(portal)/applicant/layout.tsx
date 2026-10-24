import { requireArea } from '@/lib/auth/session';

export default async function ApplicantLayout({ children }: { children: React.ReactNode }) {
  await requireArea('applicant');
  return <>{children}</>;
}
