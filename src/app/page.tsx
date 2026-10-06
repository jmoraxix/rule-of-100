import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { fmt, loadActive } from "@/lib/goals";
import SignOut from "@/components/sign-out";

export default async function Home() {
  const supabase = await createClient();
  const { data: profile } = await supabase.from("profiles").select("id").maybeSingle();
  if (!profile) redirect("/onboarding");
  const goals = await loadActive(supabase);
  if (goals.length === 0) redirect("/onboarding");
  if (goals.length === 1) redirect(`/goals/${goals[0].id}`);

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col gap-8 px-6 py-8">
      <p role="note" className="border-l-2 border-foreground pl-3 text-sm text-muted">
        The rule works with one goal. Pick one and let the rest wait.
      </p>
      <h1 className="text-3xl font-semibold tracking-tight">Your goals</h1>
      <ul className="flex flex-col divide-y divide-line border-y border-line">
        {goals.map((g) => (
          <li key={g.id}>
            <Link href={`/goals/${g.id}`} className="flex min-h-[72px] items-center justify-between gap-4 py-4">
              <span>
                <span className="block text-lg font-medium">{g.action}</span>
                <span className="block text-sm text-muted">
                  Day {g.day_number}/100 · streak {g.streak}
                </span>
              </span>
              <span className="num text-3xl font-semibold">{fmt(g, g.today_value)}</span>
            </Link>
          </li>
        ))}
      </ul>
      <div className="mt-auto flex items-center justify-between">
        <Link href="/new" className="btn btn-ghost">
          New goal
        </Link>
        <SignOut />
      </div>
    </main>
  );
}
