// features/dashboards/schema.ts
//
// Shapes and small helpers for the role home screens (step 14). No server
// imports, so client components can use it.
import type { NavIconName } from '@/lib/nav';
export { todayLabel } from '@/lib/format';
import type { NextStep } from '@/features/next-step-card/queries';
import type { ScheduleStatus } from '@/features/section-scheduling/schema';

// One destination on a staff home screen. `waiting` is how many things need
// the person's action there; null when the page has nothing to count. `icon`
// is the same icon the sidebar uses for that page.
export type WorkItem = { href: string; label: string; icon: NavIconName; waiting: number | null };

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

// ---------------------------------------------------------------
// Enrollment funnel: the share that finished, and where most people stall.
// ---------------------------------------------------------------
export type FunnelSummary = {
  total: number;
  enrolled: number;
  percent: number; // whole number, 0 to 100
  biggestGap: { from: string; to: string; count: number } | null;
};

export function funnelSummary(stages: FunnelStage[]): FunnelSummary {
  const total = stages[0]?.count ?? 0;
  const enrolled = stages[stages.length - 1]?.count ?? 0;

  let biggestGap: FunnelSummary['biggestGap'] = null;
  for (let index = 1; index < stages.length; index += 1) {
    const count = stages[index - 1].count - stages[index].count;
    if (count > 0 && (biggestGap === null || count > biggestGap.count)) {
      biggestGap = { from: stages[index - 1].label, to: stages[index].label, count };
    }
  }

  return { total, enrolled, percent: total === 0 ? 0 : Math.round((enrolled / total) * 100), biggestGap };
}

// ---------------------------------------------------------------
// Schedule pipeline: how many sections sit at each approval step.
// ---------------------------------------------------------------
export type PipelineStage = { status: ScheduleStatus; label: string; count: number };

// ---------------------------------------------------------------
// Visit capacity: seats on the coming days against the people who still
// have no visit date.
// ---------------------------------------------------------------
export type VisitDay = { date: string; label: string; booked: number; capacity: number };

export type VisitCapacityData = {
  days: VisitDay[]; // the next days that have an open slot
  freeSeats: number; // open seats on every coming open slot
  unassigned: number; // applicants with no visit date yet
};

// ---------------------------------------------------------------
// Admin: the latest changes in the audit log.
// ---------------------------------------------------------------
export type ActivityItem = { id: string; when: string; actor: string; text: string };

// ---------------------------------------------------------------
// Dean and Secretary: the sections that wait on this person.
// ---------------------------------------------------------------
export type SectionAttention = { id: string; label: string; detail: string };

// ---------------------------------------------------------------
// Time helpers. Fixed to Manila so the server and the browser print the
// same text, and "today" means the school's day.
// ---------------------------------------------------------------
const WEEKDAY_NUMBER: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

// The weekday (1 Monday to 7 Sunday, like section_subjects.day_of_week) and
// the minutes since midnight, in Manila.
export function manilaClock(now: Date = new Date()): { day: number; minutes: number } {
  const parts = new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'Asia/Manila',
  }).formatToParts(now);
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? '';
  return {
    day: WEEKDAY_NUMBER[part('weekday')] ?? 1,
    minutes: Number(part('hour')) * 60 + Number(part('minute')),
  };
}

export function toMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

export function plural(count: number, one: string, many: string): string {
  return count === 1 ? one : many;
}

// ---------------------------------------------------------------
// Professor: which class is on now, or comes next.
// ---------------------------------------------------------------
type Timed = { day: number | null; start: string; end: string };

// The class in progress, or else the next one to start this week; after the
// last class of the week, the first of the next. Classes with no time yet are
// skipped. `live` is true while the class is on.
export function nextClass<T extends Timed>(rows: T[], clock: { day: number; minutes: number }): { row: T; live: boolean } | null {
  const timed = rows
    .filter((row) => row.day !== null && row.start !== '' && row.end !== '')
    .sort((a, b) => (a.day ?? 0) - (b.day ?? 0) || a.start.localeCompare(b.start));
  if (timed.length === 0) return null;

  const upcoming = timed.find((row) => {
    const day = row.day ?? 0;
    return day > clock.day || (day === clock.day && toMinutes(row.end) > clock.minutes);
  });
  const row = upcoming ?? timed[0];
  const live = row.day === clock.day && toMinutes(row.start) <= clock.minutes && clock.minutes < toMinutes(row.end);
  return { row, live };
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
