import { ProfessorLoad } from '@/features/dashboards/ProfessorLoad';
import { getProfessorLoad } from '@/features/dashboards/queries';

export const metadata = { title: 'Professor | PLP Enrollment' };

export default async function ProfessorPage() {
  const { rows, students } = await getProfessorLoad();
  return <ProfessorLoad rows={rows} students={students} />;
}
