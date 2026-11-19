// Server-side practice verification outcome for the learner practice route.
// The database replays the learner's evidence (practice_verify_mission) and
// summarises every verified or failed run in practice_mission_runs; this
// module only maps that outcome to the HTTP reply and never evaluates work.

export type PracticeRunRow = {
  run_number: number;
  duration_seconds: number | null;
  invalid_count: number;
  correction_count: number;
  outcome: 'verified' | 'incomplete';
  failure_code: string | null;
};

export type PracticeRunMetrics = Omit<PracticeRunRow, 'outcome' | 'failure_code'>;

export type PracticeRpcError = { code?: string | null; message?: string | null } | null;

/** The three trusted database calls the route needs (service-role client). */
export type PracticeVerificationPort = {
  verify(learner: string, mission: string): Promise<PracticeRpcError>;
  recordFailure(learner: string, mission: string, failure: string): Promise<PracticeRpcError>;
  latestRun(learner: string, mission: string): Promise<PracticeRunRow | null>;
};

export type PracticeVerificationReply = {
  status: 200 | 403 | 422;
  body:
    | { verified: true; run: PracticeRunMetrics | null }
    | { error: string; failure: string | null; run: PracticeRunMetrics | null };
};

export const PRACTICE_VERIFICATION_MESSAGE =
  'Complete and verify each work phase before submitting practice evidence.';

const learnerFailure = /^PRACTICE_(?:WORK_INCOMPLETE:[a-z0-9_]{1,80}|EVIDENCE_REQUIRED)$/;

/** Only the verifier's own learner-facing codes are recorded or returned. */
export function practiceFailureCode(error: PracticeRpcError): string | null {
  const message = error?.message?.trim() ?? '';
  return learnerFailure.test(message) ? message : null;
}

export function practiceRunMetrics(
  row: PracticeRunRow | null,
  outcome: PracticeRunRow['outcome'],
  failure: string | null = null,
): PracticeRunMetrics | null {
  if (!row || row.outcome !== outcome || (row.failure_code ?? null) !== failure) return null;
  return {
    run_number: row.run_number,
    duration_seconds: row.duration_seconds,
    invalid_count: row.invalid_count,
    correction_count: row.correction_count,
  };
}

async function safeLatestRun(port: PracticeVerificationPort, learner: string, mission: string) {
  try {
    return await port.latestRun(learner, mission);
  } catch {
    return null;
  }
}

export async function verifyPracticeMission(
  port: PracticeVerificationPort,
  learner: string,
  mission: string,
): Promise<PracticeVerificationReply> {
  const error = await port.verify(learner, mission);
  if (!error) {
    return {
      status: 200,
      body: { verified: true, run: practiceRunMetrics(await safeLatestRun(port, learner, mission), 'verified') },
    };
  }
  if (error.code === '42501') {
    return { status: 403, body: { error: PRACTICE_VERIFICATION_MESSAGE, failure: null, run: null } };
  }
  const failure = practiceFailureCode(error);
  let run: PracticeRunMetrics | null = null;
  if (failure) {
    try {
      const recordError = await port.recordFailure(learner, mission, failure);
      if (!recordError) {
        run = practiceRunMetrics(await safeLatestRun(port, learner, mission), 'incomplete', failure);
      }
    } catch {
      run = null;
    }
  }
  return { status: 422, body: { error: PRACTICE_VERIFICATION_MESSAGE, failure, run } };
}
