import { notFound, redirect } from "next/navigation";
import { z } from "zod";

// The edit page's breadcrumb links here. A user's page is the edit page.
export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!z.string().uuid().safeParse(id).success) notFound();
  redirect(`/users/${id}/edit`);
}
