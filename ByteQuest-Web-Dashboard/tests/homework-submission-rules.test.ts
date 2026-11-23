import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  curriculumFromHomework, curriculumPayload, emptyCurriculum, homeworkActionSchema, homeworkErrorMessage, homeworkSubmitErrorMessage, submissionRuleSummary,
} from '../src/lib/evaluations/homework';

const id = '00000000-0000-4000-8000-000000000001';
const base = { action: 'create', class_id: id, title: 'Cable photo report', instructions: 'Attach one photo.', deadline_at: null };

test('the payload carries consistent submission rules for every format', () => {
  const draft = emptyCurriculum();
  assert.deepEqual(
    [curriculumPayload(draft).submission_format, curriculumPayload(draft).required_file_count, curriculumPayload(draft).accepted_file_types],
    ['answer_or_file', 0, 'any'], 'new homework keeps answer-or-file by default');
  const both = curriculumPayload({ ...draft, submission_format: 'answer_and_file', required_file_count: '1', accepted_file_types: 'image' });
  assert.deepEqual([both.submission_format, both.required_file_count, both.accepted_file_types], ['answer_and_file', 1, 'image']);
  const fileOnly = curriculumPayload({ ...draft, submission_format: 'file', required_file_count: '9' });
  assert.equal(fileOnly.required_file_count, 5, 'the file count is capped at the five-file limit');
  const answerOnly = curriculumPayload({ ...draft, submission_format: 'answer', required_file_count: '3', accepted_file_types: 'image' });
  assert.deepEqual([answerOnly.required_file_count, answerOnly.accepted_file_types], [0, 'any'], 'answer-only sends no file rule');
  for (const payload of [both, fileOnly, answerOnly]) {
    assert.equal(homeworkActionSchema.safeParse({ ...base, ...payload }).success, true);
  }
});

test('stored rules round-trip through the edit form', () => {
  const restored = curriculumFromHomework({ submission_format: 'answer_and_file', required_file_count: 2, accepted_file_types: 'image' });
  assert.deepEqual([restored.submission_format, restored.required_file_count, restored.accepted_file_types], ['answer_and_file', '2', 'image']);
  const legacy = curriculumFromHomework({});
  assert.equal(legacy.submission_format, 'answer_or_file', 'rows without the columns read as answer-or-file');
  assert.deepEqual(curriculumPayload(restored).required_file_count, 2);
});

test('the request schema refuses unknown rules', () => {
  assert.equal(homeworkActionSchema.safeParse({ ...base, submission_format: 'video' }).success, false);
  assert.equal(homeworkActionSchema.safeParse({ ...base, submission_format: 'file', required_file_count: 6 }).success, false);
  assert.equal(homeworkActionSchema.safeParse({ ...base, submission_format: 'file', required_file_count: 1.5 }).success, false);
  assert.equal(homeworkActionSchema.safeParse({ ...base, accepted_file_types: 'pdf' }).success, false);
  assert.equal(homeworkActionSchema.safeParse(base).success, true, 'older clients may omit every rule');
});

test('instructors read the enforced rule in plain language', () => {
  assert.equal(submissionRuleSummary({ submission_format: 'answer_and_file', required_file_count: 1, accepted_file_types: 'image' }),
    'Written answer and at least 1 image (JPG, PNG or WEBP).');
  assert.equal(submissionRuleSummary({ submission_format: 'file', required_file_count: 2, accepted_file_types: 'any' }),
    'File only — at least 2 files; no written answer.');
  assert.equal(submissionRuleSummary({ submission_format: 'answer', required_file_count: 0, accepted_file_types: 'any' }),
    'Written answer only — files are not accepted.');
  assert.equal(submissionRuleSummary({ submission_format: 'answer_or_file', required_file_count: 0, accepted_file_types: 'any' }),
    'A written answer or a file.');
});

test('server refusals map to specific learner and instructor messages', () => {
  for (const [code, text] of [
    ['HOMEWORK_FILES_REQUIRED', 'Attach the required number of files'],
    ['HOMEWORK_ANSWER_REQUIRED', 'requires a written answer'],
    ['HOMEWORK_ANSWER_NOT_ACCEPTED', 'accepts files only'],
    ['HOMEWORK_FILES_NOT_ACCEPTED', 'written answer only'],
    ['HOMEWORK_IMAGE_FILES_REQUIRED', 'images only'],
    ['HOMEWORK_SUBMISSION_RULES_INVALID', '1 to 5 required files'],
  ] as const) {
    const mapped = homeworkErrorMessage({ message: `${code}` });
    assert.ok(mapped?.error.includes(text), code);
    assert.equal(mapped?.status, 422);
  }
});

test('a missing image is named as an image for older apps that show the server text', () => {
  const missing = { message: 'HOMEWORK_FILES_REQUIRED' };
  assert.deepEqual(homeworkSubmitErrorMessage(missing, { accepted_file_types: 'image', required_file_count: 1 }),
    { error: 'Attach at least 1 image (JPG, PNG or WEBP) before submitting.', status: 422 });
  assert.equal(homeworkSubmitErrorMessage(missing, { accepted_file_types: 'image', required_file_count: 2 })?.error,
    'Attach at least 2 images (JPG, PNG or WEBP) before submitting.');
  assert.deepEqual(homeworkSubmitErrorMessage(missing, { accepted_file_types: 'any', required_file_count: 1 }), homeworkErrorMessage(missing));
  assert.deepEqual(homeworkSubmitErrorMessage(missing, null), homeworkErrorMessage(missing));
  assert.deepEqual(homeworkSubmitErrorMessage({ message: 'HOMEWORK_ANSWER_REQUIRED' }, { accepted_file_types: 'image', required_file_count: 1 }),
    homeworkErrorMessage({ message: 'HOMEWORK_ANSWER_REQUIRED' }));
});
