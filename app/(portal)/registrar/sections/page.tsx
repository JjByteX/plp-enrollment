import { SectionDocuments } from '@/features/section-documents/SectionDocuments';
import { listSectionDocuments } from '@/features/section-documents/queries';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Sections');

// Every section this term with who holds a slip and a COR, and Print links for
// issued ones. The registrar layout already checks the role (Admin included).
export default async function SectionsPage() {
  const groups = await listSectionDocuments();
  return <SectionDocuments groups={groups} canPrint parent={{ label: 'Registrar', href: '/registrar' }} />;
}
