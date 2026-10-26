// features/reschedule-request/schema.ts
//
// Input checks for a reschedule request and the Registrar's answer (step 12).
// The database enforces who may ask, one pending request per visit and the
// order of the decision; these checks give a clear message before the request
// is sent. No server imports, so client components can use it.
//
// Request input: a reason, 1 to 500 characters after trimming.
// Decision input:
//   requestId   reschedule_requests.id
//   approve     true to move the visit, false to decline
//   slotId      the slot to move to, or null for the next open slot on another date
//   note        optional on approval, required to decline, 500 characters at most

export { MAX_REASON, UUID, parseReason } from '@/lib/validate';
export { formatSlotDate, windowLabel } from '@/lib/format';
import { MAX_REASON, UUID } from '@/lib/validate';

export type DecisionInput = {
  requestId: string;
  approve: boolean;
  slotId: string | null;
  note: string;
};

export type ParsedDecision = { ok: true; value: DecisionInput } | { ok: false; reason: string };

export function parseDecisionInput(raw: unknown): ParsedDecision {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The decision is missing.' };
  }
  const body = raw as Record<string, unknown>;

  const requestId = typeof body.requestId === 'string' ? body.requestId.trim() : '';
  if (!UUID.test(requestId)) return { ok: false, reason: 'Choose a request.' };

  if (typeof body.approve !== 'boolean') return { ok: false, reason: 'Approve or decline the request.' };
  const approve = body.approve;

  let slotId: string | null = null;
  if (typeof body.slotId === 'string' && body.slotId.trim().length > 0) {
    slotId = body.slotId.trim();
    if (!UUID.test(slotId)) return { ok: false, reason: 'Choose a valid slot.' };
  }
  if (!approve && slotId) return { ok: false, reason: 'A declined request has no new slot.' };

  const note = typeof body.note === 'string' ? body.note.trim() : '';
  if (note.length > MAX_REASON) return { ok: false, reason: `The note is longer than ${MAX_REASON} characters.` };
  if (!approve && note.length === 0) return { ok: false, reason: 'Enter the reason for declining.' };

  return { ok: true, value: { requestId, approve, slotId, note } };
}
