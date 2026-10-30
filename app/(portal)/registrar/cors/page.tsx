import { CorsAdmin } from '@/features/cor/CorsAdmin';
import { listIssuedCors, listReadyForCor } from '@/features/cor/queries';
import { catchUpAdmissionsStatus } from '@/features/admissions-callback/send';

export const metadata = { title: 'COR | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) issues the COR once
// the slip is issued and payment is cleared or not required, and can print or
// reprint any issued COR. The registrar layout already checks the role.
export default async function CorsPage() {
  // Sends Admissions any status update it missed earlier. Never throws.
  await catchUpAdmissionsStatus();
  const [ready, issued] = await Promise.all([listReadyForCor(), listIssuedCors()]);
  return <CorsAdmin ready={ready} issued={issued} />;
}
