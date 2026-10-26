import { SchedulesBoard } from '@/features/section-scheduling/SchedulesBoard';
import { loadBoard, isScheduleStatus } from '@/features/section-scheduling/queries';
import { UUID } from '@/features/section-scheduling/schema';
import { requireUser } from '@/lib/auth/session';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Schedules');

// The Registrar approves or rejects schedules the Dean signed (Admin too, through the registrar area). The registrar layout already checks the role.
export default async function SchedulesPage({
  searchParams,
}: {
  searchParams: { program?: string; status?: string };
}) {
  const user = await requireUser();
  const programId = searchParams.program && UUID.test(searchParams.program) ? searchParams.program : null;
  const status = isScheduleStatus(searchParams.status) ? searchParams.status : null;
  const board = await loadBoard(user, {});

  return (
    <SchedulesBoard
      viewerRole={user.role}
      basePath="/registrar/schedules"
      programs={board.programs}
      programId={programId}
      status={status}
      sections={board.sections}
      professors={board.professors}
      rooms={board.rooms}
      waiting={board.waiting}
    />
  );
}
