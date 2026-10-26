import { PrerequisitesPageContent } from '@/features/prerequisites/PrerequisitesPageContent';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Prerequisites');

// Admin and the Dean set prerequisites; Admin sees every program. The admin layout already checks the role. The database limits what each role reads and who may edit.
export default function PrerequisitesPage({ searchParams }: { searchParams: { program?: string } }) {
  return <PrerequisitesPageContent basePath="/admin/prerequisites" searchParams={searchParams} />;
}
