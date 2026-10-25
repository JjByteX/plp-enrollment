// features/documents-and-numbering/schema.ts
//
// Types, input checks and small pure helpers for step 7 (documents and
// student numbering). No server imports, so client components can use it.
// The database enforces the real rules (required items, locks, numbering);
// these checks give the Registrar a clear message before the request is sent.
//
// Tick input, as sent from the checklist:
//   applicantId   applicants.id
//   docType       document_requirements.doc_type
//   received      true = tick, false = untick
//   note          optional, up to 200 characters, required for "other"
import { UUID } from '@/features/visit-scheduling/schema';

export { UUID };

export const MAX_NOTE = 200;
export const MAX_SEARCH = 100;

export type AdmissionType = 'new' | 'transferee' | 'foreign';

export const ADMISSION_TYPE_LABEL: Record<AdmissionType, string> = {
  new: 'New',
  transferee: 'Transferee',
  foreign: 'Foreign',
};

export function isAdmissionType(value: unknown): value is AdmissionType {
  return value === 'new' || value === 'transferee' || value === 'foreign';
}

// "other" is the Registrar's own optional tick, not a late item.
export const OTHER_DOC_TYPE = 'other';

export type Requirement = {
  docType: string;
  label: string;
  appliesTo: AdmissionType[];
  required: boolean;
  sortOrder: number;
};

export type ReceivedDocument = {
  docType: string;
  note: string | null;
  receivedAt: string;
};

export type ChecklistItem = {
  docType: string;
  label: string;
  required: boolean;
  // Not required, and not "other": never blocks promotion, stays tickable afterwards.
  late: boolean;
  received: boolean;
  note: string | null;
};

// The checklist for one applicant: every active requirement that applies to
// their admission type, in catalog order, with whether it was received.
export function buildChecklist(
  admissionType: AdmissionType,
  requirements: Requirement[],
  documents: ReceivedDocument[]
): ChecklistItem[] {
  const byType = new Map(documents.map((doc) => [doc.docType, doc]));
  return requirements
    .filter((req) => req.appliesTo.includes(admissionType))
    .sort((a, b) => a.sortOrder - b.sortOrder)
    .map((req) => {
      const doc = byType.get(req.docType);
      return {
        docType: req.docType,
        label: req.label,
        required: req.required,
        late: !req.required && req.docType !== OTHER_DOC_TYPE,
        received: doc !== undefined,
        note: doc?.note ?? null,
      };
    });
}

export type ChecklistProgress = {
  received: number; // required items received
  total: number; // required items
  missing: string[]; // labels of required items not received
};

export function checklistProgress(items: ChecklistItem[]): ChecklistProgress {
  const required = items.filter((item) => item.required);
  return {
    received: required.filter((item) => item.received).length,
    total: required.length,
    missing: required.filter((item) => !item.received).map((item) => item.label),
  };
}

// Late items (Form 137) not received yet.
export function openLateItems(items: ChecklistItem[]): string[] {
  return items.filter((item) => item.late && !item.received).map((item) => item.label);
}

// "3 of 6"
export function progressLabel(progress: ChecklistProgress): string {
  return `${progress.received} of ${progress.total}`;
}

// Case insensitive match on any of the fields (name, applicant ref, email).
export function matchesSearch(query: string, ...fields: (string | null | undefined)[]): boolean {
  const needle = query.trim().toLowerCase();
  if (needle.length === 0) return true;
  return fields.some((field) => (field ?? '').toLowerCase().includes(needle));
}

export type DocumentsTab = 'pending' | 'received' | 'withdrawn';

export type DocumentsFilter = {
  q: string;
  programId: string | undefined;
  tab: DocumentsTab;
};

function firstValue(value: unknown): unknown {
  return Array.isArray(value) ? value[0] : value;
}

// Reads the page's search parameters. Anything unexpected falls back to the default.
export function parseFilter(raw: Record<string, unknown>): DocumentsFilter {
  const q = firstValue(raw.q);
  const program = firstValue(raw.program);
  const tab = firstValue(raw.tab);
  return {
    q: typeof q === 'string' ? q.trim().slice(0, MAX_SEARCH) : '',
    programId: typeof program === 'string' && UUID.test(program) ? program : undefined,
    tab: tab === 'received' || tab === 'withdrawn' ? tab : 'pending',
  };
}

export type TickInput = {
  applicantId: string;
  docType: string;
  received: boolean;
  note: string | null;
};

export type ParsedTick = { ok: true; value: TickInput } | { ok: false; reason: string };

const DOC_TYPE = /^[a-z][a-z0-9_]{0,39}$/;

export function parseTickInput(raw: unknown): ParsedTick {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The document details are missing.' };
  }
  const body = raw as Record<string, unknown>;

  const applicantId = typeof body.applicantId === 'string' ? body.applicantId.trim() : '';
  if (!UUID.test(applicantId)) return { ok: false, reason: 'Choose an applicant.' };

  const docType = typeof body.docType === 'string' ? body.docType.trim() : '';
  if (!DOC_TYPE.test(docType)) return { ok: false, reason: 'Choose a document.' };

  if (typeof body.received !== 'boolean') return { ok: false, reason: 'Say whether the document was received.' };
  const received = body.received;

  const rawNote = typeof body.note === 'string' ? body.note.trim() : '';
  if (rawNote.length > MAX_NOTE) return { ok: false, reason: `The note is longer than ${MAX_NOTE} characters.` };
  if (received && docType === OTHER_DOC_TYPE && rawNote.length === 0) {
    return { ok: false, reason: 'Enter a note that says what the other document is.' };
  }

  return { ok: true, value: { applicantId, docType, received, note: rawNote.length > 0 ? rawNote : null } };
}

// "Mon, Nov 2, 2026" in Manila time, from a timestamp.
export function formatReceivedDate(value: string): string {
  return new Intl.DateTimeFormat('en-PH', {
    weekday: 'short',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeZone: 'Asia/Manila',
  }).format(new Date(value));
}
