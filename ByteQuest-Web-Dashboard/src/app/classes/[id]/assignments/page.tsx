import { notFound, redirect } from "next/navigation";
import { z } from "zod";

// An assignment page's breadcrumb links here. A class lists its assignments
// on the class page, so this route opens that tab instead of a 404.
export default async function ClassAssignmentsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!z.string().uuid().safeParse(id).success) notFound();
  redirect(`/classes/${id}?tab=assignments`);
}
