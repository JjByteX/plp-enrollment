'use client';

// The Registrar's COR page body: students whose slip is issued, whose payment
// is cleared (or not required) and who have no COR yet. Shares its list/table
// rendering with the slips admin page through ReadyIssueList. All changes go
// through ./actions.
import { ReadyIssueList } from '@/components/ReadyIssueList';
import type { ReadyStudent } from '@/features/assessment-slip/queries';
import { issueAllReadyCors, issueCor } from './actions';

export function CorsAdmin({ ready }: { ready: ReadyStudent[] }) {
  return (
    <ReadyIssueList
      title="Certificates of registration"
      emptyText="No COR is waiting."
      ready={ready}
      issueOne={issueCor}
      issueAll={issueAllReadyCors}
    />
  );
}
