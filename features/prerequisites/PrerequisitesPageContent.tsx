// features/prerequisites/PrerequisitesPageContent.tsx
//
// The server-side body shared by the four Prerequisites pages (Admin, Dean, Secretary and
// Registrar). Each page only says which base path it lives at. The database limits the
// programs and subjects each role may read, and who may edit.
import { requireUser } from '@/lib/auth/session';
import { PrerequisitesView } from './PrerequisitesView';
import { loadPrerequisitesPage } from './queries';

export async function PrerequisitesPageContent({
  basePath,
  searchParams,
}: {
  basePath: string;
  searchParams: { program?: string | string[] };
}) {
  const user = await requireUser();
  const { programs, programId, subjects } = await loadPrerequisitesPage(searchParams);

  return (
    <PrerequisitesView
      viewerRole={user.role}
      basePath={basePath}
      programs={programs}
      programId={programId}
      subjects={subjects}
    />
  );
}
