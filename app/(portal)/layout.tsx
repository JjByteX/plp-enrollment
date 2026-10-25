import { cookies } from 'next/headers';
import { PortalShell } from '@/components/PortalShell';
import { requireUser } from '@/lib/auth/session';
import { ROLE_LABEL, homePath } from '@/lib/auth/roles';
import { SIDEBAR_COOKIE, navFor } from '@/lib/nav';
import { getNextStep } from '@/features/next-step-card/queries';

// Authenticated shell. Signed-out visitors are sent to /login.
// Each role area checks its own role in its layout (requireArea).
// The "Your next step" card is loaded here so it appears on every page.
// The sidebar state comes from a cookie so the first paint is already right.
// An Applicant or Student can withdraw themselves until a COR is issued, and not
// again once they have withdrawn (step 17).
export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const nextStep = await getNextStep(user);
  const collapsed = cookies().get(SIDEBAR_COOKIE)?.value === 'collapsed';
  const canWithdraw =
    (user.role === 'applicant' || user.role === 'student') &&
    nextStep.kind !== 'withdrawn' &&
    !(nextStep.kind === 'student_waiting' && nextStep.cor !== null);

  return (
    <PortalShell
      userName={user.fullName}
      roleLabel={ROLE_LABEL[user.role]}
      homeHref={homePath(user.role)}
      nav={navFor(user.role)}
      defaultCollapsed={collapsed}
      nextStep={nextStep}
      canWithdraw={canWithdraw}
    >
      {children}
    </PortalShell>
  );
}
