import { PortalShell } from '@/components/PortalShell';
import { requireUser } from '@/lib/auth/session';
import { ROLE_LABEL } from '@/lib/auth/roles';
import { getNextStep } from '@/features/next-step-card/queries';

// Authenticated shell. Signed-out visitors are sent to /login.
// Each role area checks its own role in its layout (requireArea).
// The "Your next step" card is loaded here so it appears on every page.
export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const nextStep = await getNextStep(user);

  return (
    <PortalShell userName={user.fullName} roleLabel={ROLE_LABEL[user.role]} nextStep={nextStep}>
      {children}
    </PortalShell>
  );
}
