// features/dashboards/schema.ts
//
// Shapes and small helpers for the role home screens (step 14). No server
// imports, so client components can use it.
import type { NextStep } from '@/features/next-step-card/queries';

// One destination on a staff home screen. `waiting` is how many things need
// the person's action there; null when the page has nothing to count.
export type WorkItem = { href: string; label: string; waiting: number | null };

export type FunnelStage = { label: string; count: number };

export function waitingLabel(count: number): string {
  return `${count} waiting`;
}

// Items with something waiting come first; the rest keep their given order.
export function byImportance(items: WorkItem[]): WorkItem[] {
  return [...items].sort((a, b) => Number((b.waiting ?? 0) > 0) - Number((a.waiting ?? 0) > 0));
}

// True when at least one item counts something and none of them has anything waiting.
export function nothingWaiting(items: WorkItem[]): boolean {
  const counted = items.filter((item) => item.waiting !== null);
  return counted.length > 0 && counted.every((item) => item.waiting === 0);
}

export type Progress = { labels: string[]; active: number }; // active = index of the current step, labels.length when done

// Where an Applicant or Student stands in the enrollment steps. Documents are
// received at the visit, so they share its step. Payment is listed only once
// the slip says it is required (a student cannot read the program toggle).
export function enrollmentProgress(step: NextStep): Progress {
  if (step.kind !== 'student_waiting') {
    return { labels: ['Visit', 'Schedule', 'Assessment slip', 'COR'], active: 0 };
  }

  const paymentRequired = step.slip?.paymentRequired === true;
  const labels = ['Visit', 'Schedule', 'Assessment slip', ...(paymentRequired ? ['Payment'] : []), 'COR'];

  if (step.cor) return { labels, active: labels.length };
  if (!step.slip) return { labels, active: step.section?.approved ? labels.indexOf('Assessment slip') : 1 };
  if (paymentRequired && step.payment !== 'cleared') return { labels, active: labels.indexOf('Payment') };
  return { labels, active: labels.indexOf('COR') };
}
