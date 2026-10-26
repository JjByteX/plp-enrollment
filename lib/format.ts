// lib/format.ts
//
// Dates, times and pesos as the portal prints them. Every date is fixed to a
// time zone (Manila for timestamps, UTC for plain YYYY-MM-DD dates) so the
// server and the browser print the same text. No server imports, so client
// components can use it.
const MANILA = 'Asia/Manila';

const dateFormat = new Intl.DateTimeFormat('en-PH', { year: 'numeric', month: 'short', day: 'numeric', timeZone: MANILA });

const weekdayDateFormat = new Intl.DateTimeFormat('en-PH', {
  weekday: 'short',
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  timeZone: MANILA,
});

const dateTimeFormat = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: MANILA });

const longDateFormat = new Intl.DateTimeFormat('en-PH', {
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  timeZone: MANILA,
});

const slotDateFormat = new Intl.DateTimeFormat('en-PH', {
  weekday: 'short',
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC',
});

const shortDayFormat = new Intl.DateTimeFormat('en-PH', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });

const manilaDayFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: MANILA,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

const pesoFormat = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });

// "Oct 25, 2026", in Manila time, from a timestamp.
export function formatDate(value: string | Date): string {
  return dateFormat.format(new Date(value));
}

// "Mon, Nov 2, 2026", in Manila time, from a timestamp.
export function formatWeekdayDate(value: string | Date): string {
  return weekdayDateFormat.format(new Date(value));
}

// "Oct 25, 2026, 8:00 AM", in Manila time, from a timestamp.
export function formatDateTime(value: string | Date): string {
  return dateTimeFormat.format(new Date(value));
}

// "Monday, October 26, 2026": today's date for a page heading.
export function todayLabel(now: Date = new Date()): string {
  return longDateFormat.format(now);
}

// "Mon, Nov 2, 2026" from a YYYY-MM-DD slot date.
export function formatSlotDate(value: string): string {
  return slotDateFormat.format(new Date(`${value}T00:00:00Z`));
}

// "Mon, Oct 26" from a YYYY-MM-DD date.
export function formatShortDay(value: string): string {
  return shortDayFormat.format(new Date(`${value}T00:00:00Z`));
}

// "9:00 AM to 12:00 PM" from two HH:MM values, the same wording the
// database writes into notifications.window_label.
export function windowLabel(startTime: string, endTime: string): string {
  const format = (value: string) => {
    const [h, m] = value.split(':').map(Number);
    const hour = h % 12 === 0 ? 12 : h % 12;
    return `${hour}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
  };
  return `${format(startTime)} to ${format(endTime)}`;
}

// Today's date in Manila, as YYYY-MM-DD. Slots are Manila dates.
export function manilaToday(now: Date = new Date()): string {
  return manilaDayFormat.format(now);
}

// "₱1,250.00"
export function formatPeso(value: number): string {
  return pesoFormat.format(value);
}
