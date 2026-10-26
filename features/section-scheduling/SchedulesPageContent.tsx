// The server-side body shared by the Secretary / Dean schedules page and the
// Registrar schedules page. Each page only says which base path it lives at.
import { requireUser } from '@/lib/auth/session';
import { SchedulesBoard } from './SchedulesBoard';
import { isScheduleStatus, loadBoard } from './queries';
import { UUID } from './schema';

export async function SchedulesPageContent({
  basePath,
  searchParams,
}: {
  basePath: string;
  searchParams: { program?: string; status?: string };
}) {
  const user = await requireUser();
  const programId = searchParams.program && UUID.test(searchParams.program) ? searchParams.program : null;
  const status = isScheduleStatus(searchParams.status) ? searchParams.status : null;
  const board = await loadBoard(user, {});

  return (
    <SchedulesBoard
      viewerRole={user.role}
      basePath={basePath}
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
