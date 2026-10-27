// The server-side body shared by the Secretary / Dean schedules page and the
// Registrar schedules page. Each page only says which base path it lives at.
import { requireUser } from '@/lib/auth/session';
import { catchUpLeaves } from '@/features/leave-of-absence/queries';
import { listReviewStudents } from '@/features/term-close/queries';
import { SchedulesBoard } from './SchedulesBoard';
import { isScheduleStatus, loadBoard } from './queries';
import { UUID } from './schema';

export async function SchedulesPageContent({
  basePath,
  searchParams,
}: {
  basePath: string;
  searchParams: { program?: string; status?: string; tab?: string };
}) {
  const user = await requireUser();
  const programId = searchParams.program && UUID.test(searchParams.program) ? searchParams.program : null;
  const status = isScheduleStatus(searchParams.status) ? searchParams.status : null;
  const collegeStaff = user.role === 'dean' || user.role === 'college_secretary' || user.role === 'admin';
  const tab = collegeStaff && searchParams.tab === 'review' ? 'review' : 'sections';
  // A leave that has started or ended is caught up first, so the review list is current (step 23).
  await catchUpLeaves();
  // The review list is read on every load so its count shows on the tab; the database limits it to the college.
  const [board, review] = await Promise.all([loadBoard(user, {}), collegeStaff ? listReviewStudents() : Promise.resolve([])]);

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
      tab={tab}
      review={review}
    />
  );
}
