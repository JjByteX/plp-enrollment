import { SchedulesBoard } from '@/features/section-scheduling/SchedulesBoard';
import { loadBoard, isScheduleStatus } from '@/features/section-scheduling/queries';
import { UUID } from '@/features/section-scheduling/schema';
import { requireUser } from '@/lib/auth/session';

export const metadata = { title: 'Schedules | PLP Enrollment' };

// The College Secretary prepares sections and professor loading, the Dean signs off and can do the same work. The secretary layout already checks the role.
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
      basePath="/secretary/schedule"
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
