import { z } from "zod";

export const LEARNER_SEARCH_PAGE_SIZE = 15;
export const learnerSearchSchema = z.object({
  q: z.string().trim().min(2, "Enter at least two characters.").max(100)
    .refine((value) => !/[\u0000-\u001f*]/.test(value), "Use a name or email without search operators."),
  page: z.coerce.number().int().min(0).max(100).default(0),
});
export const enrollLearnerSchema = z.object({ learnerId: z.string().uuid() }).strict();

export type EnrollmentState = "not_enrolled" | "active" | "previously_enrolled";
export type EnrollmentLearner = {
  id: string;
  fullName: string;
  email: string;
  enrollment: EnrollmentState;
};

export const enrollmentLabels: Record<EnrollmentState, string> = {
  not_enrolled: "Not enrolled in this class",
  active: "Already enrolled",
  previously_enrolled: "Previously enrolled · history retained",
};

// Quote PostgREST values separately from the fixed filter grammar. Escape LIKE
// wildcards so names/emails are literal partial matches, never search operators.
export function learnerSearchFilter(term: string) {
  const pattern = `%${term.replace(/[\\%_]/g, "\\$&")}%`;
  const value = JSON.stringify(pattern);
  return `full_name.ilike.${value},email.ilike.${value}`;
}

export function learnerEnrollmentState(statuses: readonly string[]): EnrollmentState {
  return statuses.includes("active") ? "active" : statuses.length ? "previously_enrolled" : "not_enrolled";
}

export const ONE_ACTIVE_CLASS_MESSAGE =
  "This learner is already enrolled in another class. A learner can belong to only one class at a time.";

export type EnrollmentFailureCode = "ENROLLED_IN_ANOTHER_CLASS" | "ALREADY_ENROLLED" | "NOT_ELIGIBLE" | "CLASS_SCOPE" | "UNAVAILABLE";

// The database names the one-class rule by a stable code; it never names the other class.
export function enrollmentFailure(code?: string, message?: string): { status: number; code: EnrollmentFailureCode; message: string } {
  if (message?.includes("LEARNER_ALREADY_IN_ANOTHER_CLASS")) return { status: 409, code: "ENROLLED_IN_ANOTHER_CLASS", message: ONE_ACTIVE_CLASS_MESSAGE };
  if (code === "23505") return { status: 409, code: "ALREADY_ENROLLED", message: "This learner is already enrolled in this class." };
  if (code === "22023") return { status: 422, code: "NOT_ELIGIBLE", message: "This learner is no longer eligible. Search again to select an active learner." };
  if (code === "42501") return { status: 403, code: "CLASS_SCOPE", message: "You can enroll learners only in your own active class." };
  return { status: 503, code: "UNAVAILABLE", message: "Enrollment could not be confirmed. Refresh the class before trying again." };
}
