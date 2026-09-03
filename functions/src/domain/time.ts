/**
 * Timezone helpers built on Intl (no external deps). All storage is UTC; campus
 * timezone is only used to decide "which week/day" a moment belongs to.
 */

export interface LocalParts {
  year: number;
  month: number; // 1-12
  day: number; // 1-31
  hour: number; // 0-23
  minute: number;
  weekday: number; // 0 = Sunday ... 6 = Saturday
}

const partCache = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let f = partCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      weekday: "short",
    });
    partCache.set(timeZone, f);
  }
  return f;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function localParts(date: Date, timeZone: string): LocalParts {
  const parts = formatter(timeZone).formatToParts(date);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "0";
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")) % 24,
    minute: Number(get("minute")),
    weekday: WEEKDAYS.indexOf(get("weekday")),
  };
}

/** "YYYY-MM-DD" in the campus timezone. */
export function localDateKey(date: Date, timeZone: string): string {
  const p = localParts(date, timeZone);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
}

/**
 * ISO-8601 week key ("2026-W36") computed from the campus-local calendar date.
 * Weeks start Monday.
 */
export function isoWeekKey(date: Date, timeZone: string): string {
  const p = localParts(date, timeZone);
  // Work in UTC with the local calendar date so DST cannot shift the day.
  const d = new Date(Date.UTC(p.year, p.month - 1, p.day));
  const dayNum = d.getUTCDay() || 7; // Mon=1..Sun=7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum); // Thursday of this week
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${pad(week)}`;
}

/** Returns the week key immediately before `weekKey`. */
export function previousWeekKey(weekKey: string): string {
  const { year, week } = parseWeekKey(weekKey);
  // Thursday of the given ISO week:
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jan4Day = jan4.getUTCDay() || 7;
  const mondayWeek1 = new Date(jan4.getTime() - (jan4Day - 1) * 86400000);
  const monday = new Date(mondayWeek1.getTime() + (week - 1) * 7 * 86400000);
  const prev = new Date(monday.getTime() - 7 * 86400000);
  return isoWeekKey(prev, "UTC");
}

export function parseWeekKey(weekKey: string): { year: number; week: number } {
  const m = /^(\d{4})-W(\d{2})$/.exec(weekKey);
  if (!m) throw new Error(`Invalid week key ${weekKey}`);
  return { year: Number(m[1]), week: Number(m[2]) };
}

/** Difference in whole weeks between two week keys (b - a). */
export function weeksBetween(a: string, b: string): number {
  const toMonday = (k: string) => {
    const { year, week } = parseWeekKey(k);
    const jan4 = new Date(Date.UTC(year, 0, 4));
    const jan4Day = jan4.getUTCDay() || 7;
    const mondayWeek1 = new Date(jan4.getTime() - (jan4Day - 1) * 86400000);
    return new Date(mondayWeek1.getTime() + (week - 1) * 7 * 86400000).getTime();
  };
  return Math.round((toMonday(b) - toMonday(a)) / (7 * 86400000));
}

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86400000);
}

export function hourBucket(hour: number): "morning" | "afternoon" | "evening" {
  if (hour < 12) return "morning";
  if (hour < 17) return "afternoon";
  return "evening";
}

/** "YYYY-MM" settlement month key in campus time. */
export function monthKey(date: Date, timeZone: string): string {
  const p = localParts(date, timeZone);
  return `${p.year}-${pad(p.month)}`;
}

const pad = (n: number) => String(n).padStart(2, "0");
