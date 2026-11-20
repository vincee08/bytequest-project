import { redirect } from "next/navigation";

// A learner's progress page links here from its breadcrumb. The learner list
// is the Learners (progress) page itself.
export default function ProgressLearnersPage() {
  redirect("/progress");
}
