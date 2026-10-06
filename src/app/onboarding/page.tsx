import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loadActive } from "@/lib/goals";
import GoalForm from "@/components/goal-fields";
import ProfileForm from "./profile-form";

export default async function Onboarding() {
  const supabase = await createClient();
  const { data: profile } = await supabase.from("profiles").select("id").maybeSingle();
  if (profile && (await loadActive(supabase)).length > 0) redirect("/");
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-8 px-6 py-8">
      {profile ? (
        <>
          <h1 className="text-3xl font-semibold tracking-tight">What will you do 100 times a day?</h1>
          <GoalForm />
        </>
      ) : (
        <>
          <h1 className="text-3xl font-semibold tracking-tight">Welcome. What should we call you?</h1>
          <ProfileForm />
        </>
      )}
    </main>
  );
}
