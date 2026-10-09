import type { PracticeAttempt } from './database';
import type { PracticeQuestion } from './question-bank';

export function practiceQuizView(attempt: PracticeAttempt) {
  const submitted = attempt.status==='submitted';
  return {id:attempt.id,coc:attempt.coc_code,status:attempt.status,source:attempt.source,
    answers:attempt.answers,passingPercent:attempt.passing_percent,
    ...(submitted ? {score:attempt.score,percentage:(attempt.score??0)*20,passed:attempt.passed}:{}),
    questions:attempt.status==='generating' ? [] : (attempt.questions as unknown as PracticeQuestion[]).map(q=>({
      id:q.id,question:q.question,choices:q.choices,page:q.page,
      ...(submitted ? {answer:q.answer,explanation:q.explanation}:{}),
    })),
  };
}
