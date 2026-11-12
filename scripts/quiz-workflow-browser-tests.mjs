import assert from 'node:assert/strict';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const base = process.env.BQ_QUIZ_PREVIEW_URL ?? 'http://127.0.0.1:3008';
if (base !== 'http://127.0.0.1:3008') throw new Error('Dedicated local quiz preview required.');
const accountsPath = process.env.BQ_QUIZ_QA_ACCOUNT_FILE;
if (!accountsPath?.replaceAll('\\', '/').endsWith('/.tmp/quiz-preview-accounts.json')) throw new Error('Ignored local QA account file required.');
const fixture = JSON.parse(fs.readFileSync(accountsPath, 'utf8'));
const title = `Owner testing browser quiz ${Date.now().toString(36)}`;
const savedTitle = title.replace('browser quiz', 'saved browser quiz');
const { chromium } = process.env.BQ_PLAYWRIGHT_MODULE ? await import(pathToFileURL(process.env.BQ_PLAYWRIGHT_MODULE).href) : await import('playwright');
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.setDefaultTimeout(20_000);
const pass = message => console.log(`PASS ${message}`);
const screenshotDirectory = process.env.BQ_QUIZ_SCREENSHOTS;
if (screenshotDirectory) fs.mkdirSync(screenshotDirectory, { recursive: true });
try {
  await page.goto(`${base}/login`);
  await page.getByLabel('Email', { exact: true }).fill(fixture.accounts.instructor.email);
  await page.getByLabel('Password', { exact: true }).fill(fixture.accounts.instructor.password);
  await page.getByRole('button', { name: /sign in/i }).click();
  await page.waitForURL('**/instructor/dashboard');
  await page.goto(`${base}/quizzes/${fixture.quizId}`);
  await page.getByRole('tab', { name: 'Results', exact: true }).click();
  await page.getByText('4/4 · Submitted — Attempt used', { exact: true }).waitFor();
  pass('instructor sees the preserved learner result from an earlier quiz version');
  await page.goto(`${base}/quizzes`);
  await page.getByRole('heading', { name: 'Quizzes', exact: true }).waitFor();
  await page.getByLabel('Search quizzes').fill('NoSuchQuizEver');
  await page.getByText('No quizzes match your search').waitFor();
  await page.getByLabel('Search quizzes').clear();
  await page.getByRole('button', { name: 'Create quiz', exact: true }).click();
  await page.getByLabel('Quiz title').fill(title);
  await page.locator('#quiz-topic').fill('Network troubleshooting');
  await page.getByRole('button', { name: 'Create quiz & add questions' }).click();
  await page.waitForURL(/\/quizzes\/[a-f0-9-]+$/);
  const quizUrl = page.url();
  await page.getByRole('heading', { name: 'Questions', exact: true }).waitFor();
  pass('quiz library search and fast draft creation');

  let testSaveFailure = true;
  async function question(type, prompt) {
    await page.getByRole('button', { name: 'Add question', exact: true }).first().click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Question type').selectOption(type);
    await dialog.locator('#question-prompt').fill(prompt);
    if (type === 'multiple_choice' || type === 'scenario_based') {
      for (let index = 0; index < 4; index++) await dialog.locator(`#option-${index}`).fill(['Router', 'Switch', 'Keyboard', 'Monitor'][index]);
      await dialog.getByRole('radio', { name: 'Option A is correct' }).check();
    } else if (type === 'true_false') await dialog.getByRole('radio', { name: 'True', exact: true }).check();
    else await dialog.getByLabel('Correct answer', { exact: true }).fill('Router');
    if (testSaveFailure) {
      testSaveFailure = false;
      await page.route('**/rest/v1/rpc/upsert_quiz_item', route => route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ message: 'Temporary QA network failure', code: 'QA_UNAVAILABLE' }) }));
      await dialog.getByRole('button', { name: 'Save question', exact: true }).click();
      await page.getByText('Temporary QA network failure', { exact: true }).first().waitFor();
      assert.equal(await dialog.locator('#question-prompt').inputValue(), prompt);
      await page.unroute('**/rest/v1/rpc/upsert_quiz_item');
    }
    await dialog.getByRole('button', { name: 'Save question', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    await page.getByRole('heading', { name: prompt, exact: true }).waitFor();
  }
  await question('multiple_choice', 'Which device routes traffic between networks?');
  await question('true_false', 'A switch connects devices on a local network.');
  await question('identification', 'Name the device that routes packets.');
  await question('scenario_based', 'Two IP networks need a route. Choose the connecting device.');
  pass('all four question editors and answer controls');
  for (const [width, height] of [[320, 568], [768, 1024]]) {
    await page.setViewportSize({ width, height });
    await page.getByRole('button', { name: 'Add question', exact: true }).click();
    const dialog = page.getByRole('dialog');
    assert(await dialog.evaluate(element => element.scrollWidth <= element.clientWidth + 1), `editor overflow at ${width}`);
    if (screenshotDirectory) await page.screenshot({ path: `${screenshotDirectory}/editor-${width}.png` });
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  pass('failed-save recovery retains the question and responsive editor dialogs fit');
  await page.getByRole('button', { name: 'Edit question 1', exact: true }).click();
  await page.getByRole('dialog').locator('#question-prompt').fill('Edited question about routing between networks.');
  page.once('dialog', dialog => dialog.dismiss());
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  assert(await page.getByRole('dialog').isVisible());
  await page.getByRole('dialog').getByRole('button', { name: 'Save question', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await page.getByRole('heading', { name: 'Edited question about routing between networks.' }).waitFor();
  await page.getByRole('button', { name: 'Move question 1 down', exact: true }).click();
  await page.getByRole('heading', { name: 'Questions', exact: true }).waitFor();
  await question('true_false', 'Temporary draft question to remove safely.');
  await page.getByRole('button', { name: 'Remove question 5', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Remove question', exact: true }).click();
  await page.getByText('Enter a reason for rejection or removal.').waitFor();
  await page.getByLabel('Review note (required)', { exact: true }).fill('Duplicate temporary authoring test.');
  await page.getByRole('dialog').getByRole('button', { name: 'Remove question', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  pass('edit, unsaved-change dismissal guard, keyboard reorder and audited draft removal');
  await page.getByRole('button', { name: 'Review question 1', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Reject', exact: true }).click();
  await page.getByText('Enter a reason for rejection or removal.').waitFor();
  await page.getByLabel('Review note (required for rejection)').fill('Clarify the statement before class use.');
  await page.getByRole('dialog').getByRole('button', { name: 'Reject', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  for (let index = 1; index <= 4; index++) {
    await page.getByRole('button', { name: `Review question ${index}`, exact: true }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Approve question', exact: true }).click();
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
  }
  await page.getByText('4 of 4 approved', { exact: false }).waitFor();
  let attemptRequests = 0;
  const trackAttempt = request => { if (/start_learner_quiz/.test(request.url())) attemptRequests++; };
  page.on('request', trackAttempt);
  await page.getByRole('button', { name: 'Preview', exact: true }).click();
  await page.getByText('Instructor preview · no learner attempt or grade is created.').waitFor();
  await page.getByRole('dialog').getByRole('button', { name: 'Next question' }).click();
  await page.keyboard.press('Escape');
  assert.equal(attemptRequests, 0); page.off('request', trackAttempt);
  pass('explicit question approval and non-consuming preview');
  await page.getByRole('tab', { name: 'Settings', exact: true }).click();
  await page.getByLabel('Title', { exact: true }).fill(savedTitle);
  await page.getByRole('tab', { name: 'Publishing', exact: true }).click();
  await page.getByText('Save your changes before publishing.').waitFor();
  await page.getByRole('tab', { name: 'Settings', exact: true }).click();
  assert.equal(await page.getByLabel('Title', { exact: true }).inputValue(), savedTitle);
  await page.getByRole('button', { name: 'Save settings', exact: true }).click();
  await page.getByRole('heading', { name: savedTitle, exact: true }).waitFor();
  await page.getByRole('tab', { name: 'Publishing', exact: true }).click();
  assert.equal(await page.getByLabel('Publication reason', { exact: true }).count(), 0);
  await page.getByRole('checkbox').first().check();
  await page.getByRole('button', { name: 'Review & publish', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Publish quiz', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await page.getByRole('heading', { name: 'Class assignments', exact: true }).waitFor();
  pass('retained settings, saved feedback, class selection and confirmed publication without a reason');
  await page.getByRole('tab', { name: 'History', exact: true }).click();
  await page.getByRole('link', { name: 'Version 1 (viewing)' }).waitFor();
  await page.getByRole('tab', { name: 'Results', exact: true }).click();
  await page.getByRole('heading', { name: 'Learner results', exact: true }).waitFor();
  for (const [width, height] of [[320, 568], [375, 812], [768, 1024], [1440, 900]]) {
    await page.setViewportSize({ width, height });
    await page.getByRole('tab', { name: 'Questions (4)', exact: true }).click();
    await page.locator('main').evaluate(element => { element.scrollTop = 0; });
    await page.waitForTimeout(200);
    assert(await page.evaluate(() => { const main = document.querySelector('main'); return document.documentElement.scrollWidth <= innerWidth && (!main || main.scrollWidth <= main.clientWidth + 1); }), `horizontal overflow at ${width}`);
    if (width < 640) {
      const titleBox = await page.locator('main header h1').boundingBox();
      assert(titleBox.width >= width * 0.7, `header title squeezed at ${width}`);
    }
    if (screenshotDirectory) await page.screenshot({ path: `${screenshotDirectory}/quiz-${width}.png` });
  }
  await page.getByRole('tab', { name: 'Questions (4)', exact: true }).focus();
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.getByRole('tab', { name: 'Settings', exact: true }).getAttribute('aria-selected'), 'true');
  await page.goto(`${base}/quizzes`);
  await page.getByLabel('Filter quizzes').selectOption('published');
  await page.getByRole('heading', { name: savedTitle, exact: true }).waitFor();
  assert.deepEqual(errors, []);
  pass('version history, results, 320/375/768/1440 responsive layouts, keyboard tabs and no browser exceptions');
  console.log(`Owner manual-test quiz: ${quizUrl}`);
} catch (error) {
  if (screenshotDirectory) await page.screenshot({ path: `${screenshotDirectory}/failure.png`, timeout: 5_000 }).catch(() => {});
  throw error;
} finally { await browser.close(); }
