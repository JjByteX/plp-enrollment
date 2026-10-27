import { GradesBoard } from '@/features/grading/GradesBoard';
import { loadGradesPage } from '@/features/grading/queries';
import { listPendingCredits } from '@/features/prerequisites/queries';
import { requireUser } from '@/lib/auth/session';

export const metadata = { title: 'Grades | PLP Enrollment' };

// The registrar layout already checks the role. The database limits what each role reads.
export default async function GradesPage({
  searchParams,
}: {
  searchParams: { tab?: string; section?: string; subject?: string };
}) {
  const user = await requireUser();
  const { tab, ready, sections, changes, sheet, termStatus, completed, onLeave } = await loadGradesPage(searchParams, {
    lapse: true,
    registrar: true,
  });
  // Credits waiting for the Registrar are listed beside the grade changes (step 20).
  const credits = tab === 'changes' ? await listPendingCredits() : [];

  return (
    <GradesBoard
      viewerRole={user.role}
      basePath="/registrar/grades"
      tab={tab}
      sections={sections}
      changes={changes}
      sheet={sheet}
      ready={ready}
      credits={credits}
      termStatus={termStatus}
      completed={completed}
      onLeave={onLeave}
    />
  );
}
