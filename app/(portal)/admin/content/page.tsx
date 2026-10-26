import { ContentAdmin } from '@/features/content/ContentAdmin';
import { getTerm, listColleges, listRooms, listSubjects } from '@/features/content/queries';
import { UUID, parseTab } from '@/features/content/schema';
import { getScale } from '@/features/grading/queries';
import { listPrograms } from '@/features/visit-scheduling/queries';

export const metadata = { title: 'Content | PLP Enrollment' };

// Admin only (the admin layout checks the role). The tab and the chosen
// program are in the URL. Subjects are read for one program at a time; with
// none chosen, the first program by code is shown.
export default async function ContentPage({
  searchParams,
}: {
  searchParams: { tab?: string; program?: string };
}) {
  const tab = parseTab(searchParams.tab);
  const programs = await listPrograms();
  const chosen = searchParams.program && UUID.test(searchParams.program) ? searchParams.program : null;
  const programId = programs.find((program) => program.id === chosen)?.id ?? programs[0]?.id ?? null;

  const [subjects, rooms, colleges, term, scale] = await Promise.all([
    tab === 'subjects' && programId ? listSubjects(programId) : Promise.resolve([]),
    tab === 'rooms' ? listRooms() : Promise.resolve([]),
    tab === 'rooms' ? listColleges() : Promise.resolve([]),
    tab === 'term' ? getTerm() : Promise.resolve(null),
    tab === 'grading' ? getScale() : Promise.resolve({ incWindowDays: 14, bands: [] }),
  ]);

  return (
    <ContentAdmin
      tab={tab}
      programs={programs}
      programId={programId}
      subjects={subjects}
      rooms={rooms}
      colleges={colleges}
      term={term}
      scale={scale}
    />
  );
}
