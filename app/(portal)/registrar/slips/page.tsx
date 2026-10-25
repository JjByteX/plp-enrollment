import { SlipsAdmin } from '@/features/assessment-slip/SlipsAdmin';
import { listReadyStudents } from '@/features/assessment-slip/queries';

export const metadata = { title: 'Slips | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) issues the assessment
// slip once the student's schedule is approved. The registrar layout already
// checks the role.
export default async function SlipsPage() {
  const ready = await listReadyStudents();
  return <SlipsAdmin ready={ready} />;
}
