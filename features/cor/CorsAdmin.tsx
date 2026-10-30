'use client';

// The Registrar's COR page body: students whose slip is issued, whose payment
// is cleared (or not required) and who have no COR yet (Waiting), and those
// whose COR is issued this term (Issued, for reprints). Shares its rendering
// with the slips admin page through ReadyIssueList. All changes go through
// ./actions; printing goes through the /print/cor view.
import { ReadyIssueList } from '@/components/ReadyIssueList';
import type { ReadyStudent } from '@/features/assessment-slip/queries';
import { issueAllReadyCors, issueCor } from './actions';

export function CorsAdmin({ ready, issued }: { ready: ReadyStudent[]; issued: ReadyStudent[] }) {
  return (
    <ReadyIssueList
      title="Certificates of registration"
      emptyText="No COR is waiting."
      issuedEmptyText="No COR has been issued this term."
      ready={ready}
      issued={issued}
      printPath="/print/cor"
      issueOne={issueCor}
      issueAll={issueAllReadyCors}
    />
  );
}
