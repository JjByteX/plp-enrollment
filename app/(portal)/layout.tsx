import { PortalShell } from '@/components/PortalShell';
import { requireUser } from '@/lib/auth/session';
import { ROLE_LABEL } from '@/lib/auth/roles';

// Authenticated shell. Signed-out visitors are sent to /login.
// Each role area checks its own role in its layout (requireArea).
export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();

  return (
    <PortalShell userName={user.fullName} roleLabel={ROLE_LABEL[user.role]}>
      {children}
    </PortalShell>
  );
}
