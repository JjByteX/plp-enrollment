'use client';

// The Registrar's slips page body: students whose schedule is approved and who
// have no slip yet. Shares its list/table rendering with the COR admin page
// through ReadyIssueList. All changes go through ./actions.
import { ReadyIssueList } from '@/components/ReadyIssueList';
import { issueAllReadySlips, issueSlip } from './actions';
import type { ReadyStudent } from './queries';

export function SlipsAdmin({ ready }: { ready: ReadyStudent[] }) {
  return (
    <ReadyIssueList
      title="Assessment slips"
      emptyText="No slip is waiting."
      ready={ready}
      issueOne={issueSlip}
      issueAll={issueAllReadySlips}
    />
  );
}
