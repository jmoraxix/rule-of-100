import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loadActive } from "@/lib/goals";
import Daily from "@/components/daily";

export default async function GoalPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const goals = await loadActive(supabase);
  if (goals.length === 0) redirect("/");
  if (!goals.some((g) => g.id === id)) notFound();
  return <Daily initial={goals} initialId={id} />;
}
