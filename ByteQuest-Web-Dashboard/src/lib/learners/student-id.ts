import { z } from "zod";

/** Admin student ID assignment: input validation and safe error mapping. */

export const studentIdInputSchema = z.object({
  student_id: z.union([
    z.string()
      .max(64, "Use at most 64 characters.")
      // eslint-disable-next-line no-control-regex
      .refine((value) => !/[\u0000-\u001f\u007f]/.test(value), "Remove control characters.")
      .transform((value) => value.trim() || null),
    z.null(),
  ]),
}).strict();

export function studentIdFailure(error: { code?: string; message?: string }) {
  const message = error.message ?? "";
  if (error.code === "23505" || message.includes("STUDENT_ID_IN_USE")) {
    return { status: 409, message: "This student ID already belongs to another learner. Check the ID and try again." };
  }
  if (message.includes("LEARNER_PROFILE_REQUIRED")) return { status: 422, message: "Student IDs can be set only on learner accounts." };
  if (error.code === "22023" || message.includes("STUDENT_ID_INVALID")) return { status: 422, message: "Enter a student ID of at most 64 characters." };
  if (error.code === "42501") return { status: 403, message: "Only an active administrator can change student IDs." };
  return { status: 503, message: "The student ID could not be saved. Refresh the account before retrying." };
}
