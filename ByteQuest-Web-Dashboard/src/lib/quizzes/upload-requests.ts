// Quiz answers are typed text. A question that asks the learner to attach or
// upload an image or file can never be satisfied, so it cannot be saved or
// published. supabase/migrations/20261123130100_quiz_workflow_fixes.sql applies
// the same patterns on the server; keep the two in step.
const LEAD = String.raw`(?:^|[.!?;:]\s*|\n\s*|\b(?:and|then|please|also)\s+)`;
const IMAGE = String.raw`(?:images?|photos?|photographs?|pictures?|screenshots?|snapshots?)`;

const UPLOAD_REQUEST_PATTERNS: readonly RegExp[] = [
  // "Attach one image of…", "and upload a screenshot", "Take a clear photo…"
  new RegExp(
    `${LEAD}(?:attach|upload|submit|send|include|provide|take|capture|add)\\s+(?:a|an|one|two|three|your|the)\\s+(?:[a-z-]+\\s+){0,2}${IMAGE}\\b`,
    "i",
  ),
  // "Required: written answer and one image file"
  new RegExp(String.raw`\b(?:required?|requirements?)\b[^.!?\n]{0,60}\b(?:images?|photos?|pictures?|screenshots?)\s+(?:files?|attachments?)\b`, "i"),
  // "One image file is required"
  new RegExp(String.raw`\b(?:one|an?|two|three|\d)\s+(?:images?|photos?|pictures?|screenshots?)\s+(?:files?|attachments?)\b[^.!?\n]{0,40}\b(?:required|needed)\b`, "i"),
  // "Upload your file.", "Attach your report document."
  new RegExp(`${LEAD}(?:attach|upload|submit|send)\\s+(?:your|a|an|one)\\s+(?:[a-z-]+\\s+)?(?:files?|documents?|pdfs?|attachments?)\\b`, "i"),
];

export const QUIZ_UPLOAD_REQUEST_MESSAGE =
  "Quiz answers are typed text, so learners cannot attach images or files. Remove the request, or create a homework task that requires a written answer and an image.";

export function quizTextRequestsUpload(text: string | null | undefined): boolean {
  const value = text?.trim();
  return Boolean(value) && UPLOAD_REQUEST_PATTERNS.some((pattern) => pattern.test(value!));
}
