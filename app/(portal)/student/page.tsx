import { EnrollmentProgress } from '@/features/dashboards/EnrollmentProgress';
import { enrollmentProgress } from '@/features/dashboards/schema';
import { getNextStep } from '@/features/next-step-card/queries';
import { requireUser } from '@/lib/auth/session';

export const metadata = { title: 'Student | PLP Enrollment' };

// Where the Student stands. The details and actions are in the shell's next step card.
export default async function StudentPage() {
  const user = await requireUser();
  const step = await getNextStep(user);
  // Someone who withdrew has no steps left; the next step card says so.
  if (step.kind === 'withdrawn') return null;
  return <EnrollmentProgress progress={enrollmentProgress(step)} />;
}
