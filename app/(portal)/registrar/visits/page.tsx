import { VisitsAdmin } from '@/features/visit-scheduling/VisitsAdmin';
import { listPrograms, listSlots, listUnassigned } from '@/features/visit-scheduling/queries';
import { UUID, manilaToday } from '@/features/visit-scheduling/schema';

export const metadata = { title: 'Visits | PLP Enrollment' };

// The Registrar (and Admin, through the registrar area) sets up visit slots and
// assigns applicants to them. The registrar layout already checks the role.
export default async function VisitsPage({
  searchParams,
}: {
  searchParams: { program?: string; date?: string };
}) {
  const programId = searchParams.program && UUID.test(searchParams.program) ? searchParams.program : null;
  const date = searchParams.date && /^\d{4}-\d{2}-\d{2}$/.test(searchParams.date) ? searchParams.date : null;

  const [programs, slots, unassigned] = await Promise.all([
    listPrograms(),
    listSlots({ programId: programId ?? undefined }),
    programId ? listUnassigned(programId) : Promise.resolve([]),
  ]);

  return (
    <VisitsAdmin
      programs={programs}
      programId={programId}
      date={date}
      today={manilaToday()}
      slots={slots}
      unassigned={unassigned}
    />
  );
}
