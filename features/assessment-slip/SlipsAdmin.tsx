'use client';

// The Registrar's slips page body: students whose schedule is approved and who
// have no slip yet (Waiting), and those whose slip is issued this term (Issued,
// for reprints). Shares its rendering with the COR admin page through
// ReadyIssueList. All changes go through ./actions; printing goes through the
// /print/slip view.
import { ReadyIssueList } from '@/components/ReadyIssueList';
import { issueAllReadySlips, issueSlip } from './actions';
import type { ReadyStudent } from './queries';

export function SlipsAdmin({ ready, issued }: { ready: ReadyStudent[]; issued: ReadyStudent[] }) {
  return (
    <ReadyIssueList
      title="Assessment slips"
      emptyText="No slip is waiting."
      issuedEmptyText="No slip has been issued this term."
      ready={ready}
      issued={issued}
      printPath="/print/slip"
      issueOne={issueSlip}
      issueAll={issueAllReadySlips}
    />
  );
}
