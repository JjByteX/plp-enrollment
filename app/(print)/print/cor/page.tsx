import { requireArea } from '@/lib/auth/session';
import { parsePrintIds } from '@/features/assessment-slip/queries';
import { getCorsForStudents } from '@/features/cor/queries';
import { CorView } from '@/features/cor/CorView';
import { PrintSheets } from '@/components/PrintSheets';

export const metadata = { title: 'Print certificates of registration | PLP Enrollment' };

// The Registrar's (or Admin's) print view: the CORs of the students in ?ids=,
// one per page, on a page without the portal shell. Issued CORs only.
export default async function PrintCorsPage({ searchParams }: { searchParams: { ids?: string | string[] } }) {
  await requireArea('registrar');
  const { ids, capped } = parsePrintIds(searchParams.ids);
  const cors = await getCorsForStudents(ids);

  const summary = `${cors.length} certificate${cors.length === 1 ? '' : 's'} of registration${capped ? ' (first 200 only)' : ''}`;
  return (
    <PrintSheets
      backHref="/registrar/cors"
      summary={summary}
      emptyText="No issued certificate of registration to print."
      sheets={cors.map((cor) => (
        <CorView key={cor.studentNumber} cor={cor} />
      ))}
    />
  );
}
