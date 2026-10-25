import { DocumentsAdmin } from '@/features/documents-and-numbering/DocumentsAdmin';
import {
  listPendingApplicants,
  listReceivedStudents,
  listRequirements,
  listWithdrawn,
} from '@/features/documents-and-numbering/queries';
import { parseFilter } from '@/features/documents-and-numbering/schema';
import { catchUpAdmissionsStatus } from '@/features/admissions-callback/send';
import { listPrograms } from '@/features/visit-scheduling/queries';

export const metadata = { title: 'Documents | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) ticks off documents
// and marks them received. The registrar layout already checks the role.
export default async function DocumentsPage({
  searchParams,
}: {
  searchParams: Record<string, string | string[] | undefined>;
}) {
  // Sends Admissions any status update it missed earlier. Never throws.
  await catchUpAdmissionsStatus();

  const filter = parseFilter(searchParams);

  const [programs, requirements] = await Promise.all([listPrograms(), listRequirements()]);
  const pending = filter.tab === 'pending' ? await listPendingApplicants(filter, requirements) : [];
  const received = filter.tab === 'received' ? await listReceivedStudents(filter, requirements) : [];
  const withdrawn = filter.tab === 'withdrawn' ? await listWithdrawn(filter) : [];

  return (
    <DocumentsAdmin
      filter={filter}
      programs={programs}
      requirements={requirements}
      pending={pending}
      received={received}
      withdrawn={withdrawn}
    />
  );
}
