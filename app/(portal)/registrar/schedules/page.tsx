import { SchedulesPageContent } from '@/features/section-scheduling/SchedulesPageContent';
import { pageTitle } from '@/lib/pageTitle';

export const metadata = pageTitle('Schedules');

// The Registrar approves or rejects schedules the Dean signed (Admin too, through the registrar area). The registrar layout already checks the role.
export default function SchedulesPage({ searchParams }: { searchParams: { program?: string; status?: string } }) {
  return <SchedulesPageContent basePath="/registrar/schedules" searchParams={searchParams} />;
}
