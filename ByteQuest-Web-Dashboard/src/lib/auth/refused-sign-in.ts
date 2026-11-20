type SignOutScope = "global" | "local" | "others";

interface SignOutCapable {
  signOut(options?: { scope?: SignOutScope }): Promise<unknown>;
}

/**
 * Ends only the session this browser sign-in just created.
 *
 * The dashboard refuses learner, inactive and profile-less accounts after
 * signing them in. Supabase's default sign-out scope is global, which revokes
 * every session the person has: a learner who tried the staff dashboard was
 * silently signed out of the learner app, whose dashboard-API features
 * (homework, practice verification) then failed until the next sign-in.
 */
export async function endRefusedSignIn(auth: SignOutCapable): Promise<void> {
  await auth.signOut({ scope: "local" });
}
