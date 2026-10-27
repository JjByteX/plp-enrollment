// features/term-close/schema.ts
//
// Types and small helpers for closing a term and the lists it leaves behind (step 21).
// No server imports, so client components can use it. The database decides everything
// (who may close, what is missing, who is promoted); these helpers only word it.

export type TermRef = { schoolYear: string; semester: string };

export type MissingSheet = { label: string; code: string }; // BSIT 1A, COMP 101

export type TermStatus = {
  term: TermRef | null; // null until Admin sets the term
  closed: boolean;
  enrolled: number;
  missing: MissingSheet[]; // the first few section subjects without Dean-approved grades
  missingTotal: number;
};

// kind 'leave' is a student whose leave of absence ended and who has not returned yet (step 23); the
// term is then the return term, and the year level is the last one the student was enrolled in.
export type ReviewStudent = {
  kind: 'review' | 'leave';
  studentId: string;
  studentNumber: string;
  fullName: string;
  programCode: string;
  yearLevel: number;
  schoolYear: string;
  semester: string;
  reason: string; // for example "Incomplete in COMP 104"
};

export type CompletedStudent = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  programCode: string;
  schoolYear: string;
  semester: string;
};

export type CloseSummary = { promote: number; review: number; completed: number };

// Why the Close term button is disabled, naming what is missing. Null when closing is allowed.
export function closeBlockedReason(status: TermStatus): string | null {
  if (status.term === null) return 'No term is set. Ask Admin to set it in Content, Term.';
  if (status.closed) return 'This term is closed.';
  if (status.missingTotal > 0) {
    const names = status.missing.map((item) => `${item.label} ${item.code}`).join(', ');
    const more = status.missingTotal > status.missing.length ? ` and ${status.missingTotal - status.missing.length} more` : '';
    return `Grades are not approved yet for: ${names}${more}.`;
  }
  return null;
}

function count(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`;
}

// The line shown after a term is closed.
export function closeMessage(summary: CloseSummary): string {
  const parts = [
    `${count(summary.promote, 'student passed', 'students passed')} everything and will be placed when Admin opens the next term`,
    `${summary.review} on the review list`,
    `${summary.completed} completed`,
  ];
  return `Term closed. ${parts.join(', ')}.`;
}
