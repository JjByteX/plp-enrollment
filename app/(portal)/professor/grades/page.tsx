import { GradesBoard } from '@/features/grading/GradesBoard';
import { loadGradesPage } from '@/features/grading/queries';
import { requireUser } from '@/lib/auth/session';

export const metadata = { title: 'Grades | PLP Enrollment' };

// The professor layout already checks the role. The database limits what each role reads.
export default async function GradesPage({
  searchParams,
}: {
  searchParams: { tab?: string; section?: string; subject?: string };
}) {
  const user = await requireUser();
  const { tab, ready, sections, changes, sheet } = await loadGradesPage(searchParams, { lapse: false });

  return (
    <GradesBoard
      viewerRole={user.role}
      basePath="/professor/grades"
      tab={tab}
      sections={sections}
      changes={changes}
      sheet={sheet}
      ready={ready}
    />
  );
}
