import { ProfessorLoad } from '@/features/dashboards/ProfessorLoad';
import { getProfessorLoad } from '@/features/dashboards/queries';
import { manilaClock, todayLabel } from '@/features/dashboards/schema';

export const metadata = { title: 'Professor | PLP Enrollment' };

// The clock is read here, on the server, so "today" and "next class" are the
// same in the browser as in the first paint.
export default async function ProfessorPage() {
  const { rows, students } = await getProfessorLoad();
  return <ProfessorLoad rows={rows} students={students} clock={manilaClock()} today={todayLabel()} />;
}
