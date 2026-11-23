import { escapeCsvCell } from "@/lib/csv";
import { describePeriod, outcomeLabel, reasonText, statusPresentation } from "@/lib/analytics/format";
import type {
  AnalyticsErrorCode,
  AnalyticsOverview,
  ClassPerformance,
  CriteriaAnalytics,
  FilterOptions,
  LearnerPerformance,
  LearnerProfile,
  MissionAnalytics,
  QuizAnalytics,
} from "@/lib/analytics/performance-types";
import type { LearnerStatusState } from "@/lib/analytics/learner-status";
import type { AnalyticsTab } from "@/lib/analytics/query";

export type CsvCell = string | number | null;
export type AnalyticsTable = {
  title: string;
  columns: Array<{ key: string; label: string }>;
  rows: Array<Record<string, CsvCell>>;
};

export type AnalyticsTabData =
  | { tab: "overview"; data: AnalyticsOverview }
  | { tab: "classes"; data: ClassPerformance }
  | { tab: "learners"; data: LearnerPerformance }
  | { tab: "quizzes"; data: QuizAnalytics }
  | { tab: "missions"; data: MissionAnalytics }
  | { tab: "criteria"; data: CriteriaAnalytics };

/** Result of loading one analytics page: data, or an inline (non-crashing) error state. */
export type AnalyticsViewResult =
  | { ok: true; options: FilterOptions; view: AnalyticsTabData; learnerStatus?: LearnerStatusState }
  | { ok: false; code: AnalyticsErrorCode; options: FilterOptions | null };

const columns = (...pairs: Array<[string, string]>) => pairs.map(([key, label]) => ({ key, label }));

export function overviewTable(data: AnalyticsOverview): AnalyticsTable {
  const period = describePeriod(data.period);
  const population = `${data.population.description} (${data.population.enrolled})`;
  const metric = (section: string, name: string, value: CsvCell, unit = "") => ({ section, metric: name, value, unit, population, period });
  return {
    title: "Analytics overview",
    columns: columns(["section", "Section"], ["metric", "Metric"], ["value", "Value"], ["unit", "Unit"], ["population", "Population"], ["period", "Period"]),
    rows: [
      metric("Population", "Enrolled learners", data.population.enrolled, "learners"),
      metric("Population", "Active in period", data.population.active_in_period, "learners"),
      metric("Population", "Completed every required item", data.population.completed, "learners"),
      metric("Assessments", "Released results", data.assessments.released, "results"),
      metric("Assessments", "Pending release", data.assessments.pending_release, "attempts"),
      metric("Assessments", "Average released score", data.assessments.avg_percent, "%"),
      metric("Assessments", "Competent rate", data.assessments.competent_rate, "%"),
      metric("Quizzes", "Submitted", data.quizzes.submitted, "attempts"),
      metric("Quizzes", "Pending evaluation or release", data.quizzes.pending, "attempts"),
      metric("Quizzes", "Average score", data.quizzes.avg_percent, "%"),
      metric("Quizzes", "Completion rate", data.quizzes.completion_rate, "%"),
      metric("Homework", "Submitted", data.homework.submitted, "submissions"),
      metric("Homework", "Released grades", data.homework.released, "submissions"),
      metric("Homework", "Pending evaluation", data.homework.pending_evaluation, "submissions"),
      metric("Homework", "Missing", data.homework.missing, "learner-homework pairs"),
      metric("Homework", "Late", data.homework.late, "submissions"),
      metric("Homework", "Average released score", data.homework.avg_percent, "% of maximum score"),
      metric("Homework", "Completion rate", data.homework.completion_rate, "%"),
      metric("Evaluation", "Evaluate", data.evaluation.total.evaluate, "items"),
      metric("Evaluation", "Finalize", data.evaluation.total.finalize, "items"),
      metric("Evaluation", "Release", data.evaluation.total.release, "items"),
      metric("Evaluation", "Released", data.evaluation.total.released, "items"),
      metric("Evaluation", "Quizzes awaiting evaluation, finalization or release",
        data.evaluation.quiz.evaluate + data.evaluation.quiz.finalize + data.evaluation.quiz.release, "attempts"),
      metric("Practice missions", "Verified completions in period", data.missions.verified, "completions"),
      metric("Practice missions", "Completion to date", data.missions.completion_rate, "%"),
      metric("Practice missions", "Recorded runs", data.missions.runs, "runs"),
      metric("Practice missions", "Successful runs", data.missions.successful_runs, "runs"),
      metric("Practice missions", "Failed runs", data.missions.failed_runs, "runs"),
      metric("Practice missions", "Average completion time", data.missions.avg_duration_seconds, "seconds"),
      metric("Learning progress", "Average progress", data.learning_progress.avg_percent, "%"),
    ],
  };
}

export function classesTable(data: ClassPerformance): AnalyticsTable {
  const rows = data.classes.map((row) => ({
    class: row.title, enrolled: row.enrolled, active: row.active_in_period, avg_score: row.avg_score,
    quiz_avg: row.quiz_avg, competent_rate: row.assessment_competent_rate, mission_rate: row.mission_completion_rate,
    assignment_rate: row.assignment_completion_rate, progress: row.progress_avg,
    highest: row.highest ? `${row.highest.name} (${row.highest.score})` : null,
    lowest: row.lowest ? `${row.lowest.name} (${row.lowest.score})` : null,
  }));
  rows.push({
    class: "All selected classes", enrolled: data.summary.enrolled, active: data.summary.active_in_period,
    avg_score: data.summary.avg_score, quiz_avg: data.summary.quiz_avg, competent_rate: data.summary.assessment_competent_rate,
    mission_rate: data.summary.mission_completion_rate, assignment_rate: data.summary.assignment_completion_rate,
    progress: data.summary.progress_avg, highest: null, lowest: null,
  });
  return {
    title: "Class performance",
    columns: columns(
      ["class", "Class"], ["enrolled", "Enrolled"], ["active", "Active in period"], ["avg_score", "Average score (%)"],
      ["quiz_avg", "Quiz average (%)"], ["competent_rate", "Assessment competent rate (%)"],
      ["mission_rate", "Mission completion (%)"], ["assignment_rate", "Homework completion (%)"],
      ["progress", "Learning progress (%)"], ["highest", "Highest learner"], ["lowest", "Lowest learner"],
    ),
    rows,
  };
}

export function learnersTable(data: LearnerPerformance): AnalyticsTable {
  return {
    title: "Learner performance",
    columns: columns(
      ["learner", "Learner"], ["student_id", "Student ID"], ["classes", "Classes"], ["status", "Status"],
      ["reasons", "Reasons"], ["progress", "Learning progress (%)"], ["score", "Performance score (%)"],
      ["quiz_avg", "Quiz average (%)"], ["released", "Released assessments"], ["competent", "Competent results"],
      ["pending", "Pending assessments"], ["verified", "Missions verified"], ["runs", "Practice runs"],
      ["submitted", "Homework submitted"], ["pending_evaluation", "Homework pending evaluation"],
      ["missing", "Homework missing"], ["late", "Homework late"], ["last_activity", "Last activity"],
      ["points", "Engagement: points"], ["points_in_period", "Engagement: points in period"], ["level", "Engagement: level"],
    ),
    rows: data.learners.map((row) => ({
      learner: row.name, student_id: row.student_id, classes: row.classes.map((item) => item.title).join("; "),
      status: statusPresentation(row.status).label, reasons: row.reasons.map(reasonText).join("; "),
      progress: row.progress_percent, score: row.performance_score, quiz_avg: row.quiz_avg,
      released: row.assessment.released, competent: row.assessment.competent, pending: row.assessment.pending,
      verified: row.missions_verified, runs: row.practice_runs, submitted: row.assignments.submitted,
      pending_evaluation: row.assignments.pending_evaluation, missing: row.assignments.missing,
      late: row.assignments.late, last_activity: row.last_activity_at,
      points: row.engagement.points, points_in_period: row.engagement.points_in_period, level: row.engagement.level_title,
    })),
  };
}

export function quizzesTable(data: QuizAnalytics): AnalyticsTable {
  if (data.quiz) {
    return {
      title: `Quiz results - ${data.quiz.title}`,
      columns: columns(
        ["learner", "Learner"], ["student_id", "Student ID"], ["class", "Class"], ["status", "Submission status"],
        ["score", "Score (points)"], ["max", "Maximum (points)"], ["percent", "Score (%)"], ["stage", "Evaluation stage"],
        ["submitted_at", "Submitted at"],
      ),
      rows: data.results.map((row) => ({
        learner: row.name, student_id: row.student_id, class: row.class_title, status: row.status.replace("_", " "),
        score: row.score, max: row.max_score, percent: row.percent, stage: row.stage, submitted_at: row.submitted_at,
      })),
    };
  }
  return {
    title: "Quiz analytics",
    columns: columns(
      ["quiz", "Quiz"], ["coc", "COC"], ["status", "Status"], ["release_mode", "Results"], ["participants", "Participants"], ["eligible", "Eligible"],
      ["completion", "Completion rate (%)"], ["average", "Average (%)"], ["highest", "Highest (%)"], ["lowest", "Lowest (%)"],
      ["pending", "Pending evaluation"],
    ),
    rows: data.quizzes.map((row) => ({
      quiz: row.title, coc: row.coc_code?.toUpperCase() ?? null, status: row.status,
      release_mode: row.release_mode === "instructor_release" ? "After instructor release" : row.release_mode === "immediate" ? "Immediate" : null,
      participants: row.participants,
      eligible: row.eligible, completion: row.completion_rate, average: row.average, highest: row.highest,
      lowest: row.lowest, pending: row.pending,
    })),
  };
}

export function missionsTable(data: MissionAnalytics): AnalyticsTable {
  const assessmentByMission = new Map(data.assessments.map((row) => [row.mission_code, row]));
  const codes = [...new Set([...data.missions.map((row) => row.mission_code), ...data.assessments.map((row) => row.mission_code)])].sort();
  return {
    title: "Mission performance",
    columns: columns(
      ["mission", "Mission"], ["title", "Title"], ["module", "Module"], ["attempted", "Practice: learners attempted (period)"],
      ["verified", "Practice: learners verified (period)"], ["runs", "Practice: runs (period)"],
      ["successful", "Practice: successful runs (period)"], ["failed", "Practice: failed runs (period)"],
      ["per_learner", "Practice: runs per learner (period)"], ["duration", "Practice: average completion time in s (period)"],
      ["invalid", "Practice: invalid actions per run (period)"], ["verified_to_date", "Practice: learners verified (to date)"],
      ["completion", "Practice: completion rate (%) (to date)"],
      ["most_missed", "Practice: most-missed steps (period)"],
      ["a_attempts", "Assessment: attempts"], ["a_released", "Assessment: released"], ["a_competent", "Assessment: competent"],
      ["a_nyc", "Assessment: not yet competent"], ["a_pending", "Assessment: pending"], ["a_avg", "Assessment: average (%)"],
    ),
    rows: codes.map((code) => {
      const practice = data.missions.find((row) => row.mission_code === code);
      const assessment = assessmentByMission.get(code);
      return {
        mission: code.toUpperCase().replace("_", " "), title: practice?.title ?? assessment?.title ?? null,
        module: practice?.module?.code ?? null, attempted: practice?.learners_attempted ?? null,
        verified: practice?.learners_verified ?? null, verified_to_date: practice?.learners_verified_to_date ?? null,
        completion: practice?.completion_rate_to_date ?? null,
        most_missed: practice?.most_missed.length
          ? practice.most_missed.map((step) => `${step.step ? `Step ${step.step} ` : ""}${step.title} (${step.missed}/${step.runs} runs, ${step.avg_incorrect ?? 0} incorrect per run)`).join("; ")
          : null,
        runs: practice?.runs ?? null, successful: practice?.successful_runs ?? null, failed: practice?.failed_runs ?? null,
        per_learner: practice?.avg_runs_per_learner ?? null, duration: practice?.avg_duration_seconds ?? null,
        invalid: practice?.avg_invalid_actions ?? null, a_attempts: assessment?.attempts ?? null,
        a_released: assessment?.released ?? null, a_competent: assessment?.competent ?? null,
        a_nyc: assessment?.not_yet_competent ?? null, a_pending: assessment?.pending ?? null,
        a_avg: assessment?.avg_percent ?? null,
      };
    }),
  };
}

export function criteriaTable(data: CriteriaAnalytics): AnalyticsTable {
  const strongest = new Set(data.strongest.map((row) => row.criterion_id));
  const weakest = new Set(data.weakest.map((row) => row.criterion_id));
  return {
    title: "Criterion analysis",
    columns: columns(
      ["code", "Criterion code"], ["title", "Criterion"], ["source", "Source"], ["activity", "Activity"], ["mission", "Mission"],
      ["steps", "Simulation steps"], ["max", "Maximum"],
      ["avg", "Average score"], ["percent", "Percent (%)"], ["learners", "Learners evaluated"], ["satisfied", "Satisfied"],
      ["not_satisfied", "Not satisfied"], ["rank", "Rank"],
    ),
    rows: data.criteria.map((row) => ({
      code: row.code, title: row.title, source: row.source, activity: row.activity_title,
      mission: row.mission_title ?? row.mission_code,
      steps: row.steps.length ? row.steps.map((step) => (step.step ? `Step ${step.step} ${step.title}` : step.title)).join("; ") : null,
      max: row.max,
      avg: row.avg, percent: row.percent, learners: row.evaluated_learners, satisfied: row.satisfied,
      not_satisfied: row.not_satisfied,
      rank: strongest.has(row.criterion_id) ? "Strongest" : weakest.has(row.criterion_id) ? "Weakest" : null,
    })),
  };
}

export function learnerProfileTable(data: LearnerProfile): AnalyticsTable {
  return {
    title: `Learner activity - ${data.learner.name}`,
    columns: columns(["at", "Time"], ["kind", "Activity"], ["title", "Item"], ["detail", "Detail"]),
    rows: data.timeline.map((row) => ({
      at: row.at, kind: row.kind.replaceAll("_", " "), title: row.title,
      detail: Object.entries(row.detail)
        .filter(([, value]) => value !== null && value !== undefined)
        .map(([key, value]) => `${key.replaceAll("_", " ")}: ${key === "outcome" ? outcomeLabel(String(value)) : String(value)}`)
        .join("; "),
    })),
  };
}

export function analyticsTable(input: AnalyticsTabData): AnalyticsTable {
  switch (input.tab) {
    case "overview": return overviewTable(input.data);
    case "classes": return classesTable(input.data);
    case "learners": return learnersTable(input.data);
    case "quizzes": return quizzesTable(input.data);
    case "missions": return missionsTable(input.data);
    case "criteria": return criteriaTable(input.data);
  }
}

/** UTF-8 BOM + CRLF, formula-safe cells (same format as the existing report export). */
export function tableToCsv(table: AnalyticsTable): string {
  const lines = [
    table.columns.map((column) => escapeCsvCell(column.label)).join(","),
    ...table.rows.map((row) => table.columns.map((column) => escapeCsvCell(row[column.key] ?? null)).join(",")),
  ];
  return `﻿${lines.join("\r\n")}`;
}

export function analyticsCsvFilename(tab: AnalyticsTab | "learner", date: Date = new Date()): string {
  return `bytequest-analytics-${tab}-${date.toISOString().slice(0, 10)}.csv`;
}
