import { PrerequisitesPageContent } from '@/features/prerequisites/PrerequisitesPageContent';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Prerequisites');

// The Registrar can read prerequisites for every program but not change them. The registrar layout already checks the role. The database limits what each role reads and who may edit.
export default function PrerequisitesPage({ searchParams }: { searchParams: { program?: string } }) {
  return <PrerequisitesPageContent basePath="/registrar/prerequisites" searchParams={searchParams} />;
}
