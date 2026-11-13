import assert from 'node:assert/strict';
import { test } from 'node:test';
import { latenessDuration, manilaDate, manilaInputToUtc, utcToManilaInput } from '../src/lib/activities/dates';

test('Manila input round trips to UTC independent of runtime time zone', () => {
  assert.equal(manilaInputToUtc('2026-11-13T16:30'),'2026-11-13T08:30:00.000Z');
  assert.equal(utcToManilaInput('2026-11-13T08:30:00Z'),'2026-11-13T16:30');
  assert.equal(manilaInputToUtc(''),null);
  assert.equal(utcToManilaInput(null),'');
  assert.match(manilaDate('2026-11-13T08:30:00Z'), /4:30.*PM.*Manila/i);
  for (const value of ['2026-02-30T12:00','2026-01-01','invalid','2026-11-13T25:00']) assert.throws(()=>manilaInputToUtc(value));
});
test('late duration retains days, hours and minutes without whole-hour rounding', () => {
  assert.equal(latenessDuration(25*60),'25 minutes');
  assert.equal(latenessDuration((3*60+10)*60),'3 hours, 10 minutes');
  assert.equal(latenessDuration((24+4)*3600),'1 day, 4 hours');
  assert.equal(latenessDuration(195300),'2 days, 6 hours, 15 minutes');
  assert.equal(latenessDuration(0),'On time');
  assert.equal(latenessDuration(0.001),'Less than 1 minute');
  assert.equal(latenessDuration(3599),'59 minutes');
});
