import { SectionDocuments } from '@/features/section-documents/SectionDocuments';
import { listSectionDocuments } from '@/features/section-documents/queries';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Sections');

// Read only: the College Secretary and the Dean see who holds a slip and a COR
// in their own college's sections. The secretary layout already checks the
// role; the database limits the rows to the person's college.
export default async function SectionsPage() {
  const groups = await listSectionDocuments();
  return <SectionDocuments groups={groups} canPrint={false} parent={{ label: 'College Secretary', href: '/secretary' }} />;
}
