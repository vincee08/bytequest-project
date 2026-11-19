import assert from 'node:assert/strict';
import { test } from 'node:test';
import { releaseConfirmationText } from '../src/lib/evaluations/display';

// Only homework.released delivers a learner notification
// (private.deliver_activity_notification); technical and quiz releases do
// not. The confirmation must not promise a notification it cannot send.
test('a homework-only release promises the notification homework sends', () => {
  assert.match(releaseConfirmationText([{ kind: 'homework' }]), /receive a notification/);
});

test('technical and quiz releases do not promise a notification', () => {
  for (const kinds of [[{ kind: 'technical' as const }], [{ kind: 'quiz' as const }], [{ kind: 'technical' as const }, { kind: 'quiz' as const }]]) {
    const text = releaseConfirmationText(kinds);
    assert.doesNotMatch(text, /notification/);
    assert.match(text, /next time they open or refresh/);
    assert.match(text, /cannot be undone/);
  }
});

test('a mixed release names which learners are notified', () => {
  const text = releaseConfirmationText([{ kind: 'homework' }, { kind: 'quiz' }]);
  assert.match(text, /Homework learners also receive a notification/);
  assert.match(text, /cannot be undone/);
});
