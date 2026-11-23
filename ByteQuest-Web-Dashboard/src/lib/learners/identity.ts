export const UNNAMED_LEARNER = "Unnamed learner";

type LearnerProfile = { full_name?: string | null; email?: string | null } | null | undefined;

/** The learner's own name, then their email; never a class title or a product label. */
export function learnerDisplayName(profile: LearnerProfile): string {
  return profile?.full_name?.trim() || profile?.email?.trim() || UNNAMED_LEARNER;
}

/** The email shown under the name, or null when the name line already is the email. */
export function learnerSecondaryEmail(profile: LearnerProfile): string | null {
  const email = profile?.email?.trim();
  return email && profile?.full_name?.trim() ? email : null;
}
