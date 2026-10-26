import { SchedulesPageContent } from '@/features/section-scheduling/SchedulesPageContent';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Schedules');

// The College Secretary prepares sections and professor loading, the Dean signs off and can do the same work. The secretary layout already checks the role.
export default function SchedulesPage({ searchParams }: { searchParams: { program?: string; status?: string } }) {
  return <SchedulesPageContent basePath="/secretary/schedule" searchParams={searchParams} />;
}
