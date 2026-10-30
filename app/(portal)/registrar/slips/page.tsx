import { SlipsAdmin } from '@/features/assessment-slip/SlipsAdmin';
import { listIssuedStudents, listReadyStudents } from '@/features/assessment-slip/queries';

export const metadata = { title: 'Slips | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) issues the assessment
// slip once the student's schedule is approved, and can print or reprint any
// issued slip. The registrar layout already checks the role.
export default async function SlipsPage() {
  const [ready, issued] = await Promise.all([listReadyStudents(), listIssuedStudents('assessment_slips')]);
  return <SlipsAdmin ready={ready} issued={issued} />;
}
