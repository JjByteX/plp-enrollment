import { CorsAdmin } from '@/features/cor/CorsAdmin';
import { listReadyForCor } from '@/features/cor/queries';
import { catchUpAdmissionsStatus } from '@/features/admissions-callback/send';

export const metadata = { title: 'COR | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) issues the COR once
// the slip is issued and payment is cleared or not required. The registrar
// layout already checks the role.
export default async function CorsPage() {
  // Sends Admissions any status update it missed earlier. Never throws.
  await catchUpAdmissionsStatus();
  const ready = await listReadyForCor();
  return <CorsAdmin ready={ready} />;
}
