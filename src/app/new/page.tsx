import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loadActive } from "@/lib/goals";
import GoalForm from "@/components/goal-fields";

export default async function NewGoal() {
  const supabase = await createClient();
  const { data: profile } = await supabase.from("profiles").select("id").maybeSingle();
  if (!profile) redirect("/onboarding");
  const goals = await loadActive(supabase);
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col gap-8 px-6 py-8">
      <Link href="/" className="link self-start text-sm text-muted">
        Back
      </Link>
      <h1 className="text-3xl font-semibold tracking-tight">New goal</h1>
      <GoalForm confirmFirst={goals.length > 0} />
    </main>
  );
}
