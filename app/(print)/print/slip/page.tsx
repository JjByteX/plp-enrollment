import { requireArea } from '@/lib/auth/session';
import { getSlipsForStudents, parsePrintIds } from '@/features/assessment-slip/queries';
import { SlipView } from '@/features/assessment-slip/SlipView';
import { PrintSheets } from '@/components/PrintSheets';

export const metadata = { title: 'Print assessment slips | PLP Enrollment' };

// The Registrar's (or Admin's) print view: the slips of the students in ?ids=,
// one per page, on a page without the portal shell. Issued slips only.
export default async function PrintSlipsPage({ searchParams }: { searchParams: { ids?: string | string[] } }) {
  await requireArea('registrar');
  const { ids, capped } = parsePrintIds(searchParams.ids);
  const slips = await getSlipsForStudents(ids);

  const summary = `${slips.length} assessment slip${slips.length === 1 ? '' : 's'}${capped ? ' (first 200 only)' : ''}`;
  return (
    <PrintSheets
      backHref="/registrar/slips"
      summary={summary}
      emptyText="No issued assessment slip to print."
      sheets={slips.map((slip) => (
        <SlipView key={slip.studentNumber} slip={slip} />
      ))}
    />
  );
}
