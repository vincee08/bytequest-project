/** Explicit Manila wall time, independent of the browser/server time zone. */
export function manilaInputToUtc(value: string): string | null {
  if (!value) return null;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw new Error('Choose a valid date and time.');
  const date = new Date(`${value}:00+08:00`);
  if (!Number.isFinite(date.getTime()) || utcToManilaInput(date.toISOString()) !== value)
    throw new Error('Choose a valid date and time.');
  return date.toISOString();
}
export function utcToManilaInput(value: string | null): string {
  return value ? new Date(new Date(value).getTime() + 8 * 3600000).toISOString().slice(0, 16) : '';
}
export function manilaDate(value: string | null): string {
  return value ? `${new Intl.DateTimeFormat('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))} (Manila)` : 'No deadline';
}
export function latenessDuration(seconds: number): string {
  if (seconds <= 0) return 'On time';
  let minutes = Math.floor(seconds / 60);
  if (minutes === 0) return 'Less than 1 minute';
  const days = Math.floor(minutes / 1440); minutes %= 1440;
  const hours = Math.floor(minutes / 60); minutes %= 60;
  return [[days, 'day'], [hours, 'hour'], [minutes, 'minute']]
    .filter(([value]) => Number(value) > 0)
    .map(([value, unit]) => `${value} ${unit}${Number(value) === 1 ? '' : 's'}`).join(', ');
}
