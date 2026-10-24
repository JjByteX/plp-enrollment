import { DocumentsAdmin } from '@/features/documents-and-numbering/DocumentsAdmin';
import {
  listPendingApplicants,
  listReceivedStudents,
  listRequirements,
} from '@/features/documents-and-numbering/queries';
import { parseFilter } from '@/features/documents-and-numbering/schema';
import { listPrograms } from '@/features/visit-scheduling/queries';

export const metadata = { title: 'Documents | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) ticks off documents
// and marks them received. The registrar layout already checks the role.
export default async function DocumentsPage({
  searchParams,
}: {
  searchParams: Record<string, string | string[] | undefined>;
}) {
  const filter = parseFilter(searchParams);

  const [programs, requirements] = await Promise.all([listPrograms(), listRequirements()]);
  const pending = filter.tab === 'pending' ? await listPendingApplicants(filter, requirements) : [];
  const received = filter.tab === 'received' ? await listReceivedStudents(filter, requirements) : [];

  return (
    <DocumentsAdmin
      filter={filter}
      programs={programs}
      requirements={requirements}
      pending={pending}
      received={received}
    />
  );
}
