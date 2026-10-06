import type { SupabaseClient } from "@supabase/supabase-js";

export type Goal = {
  id: string;
  action: string;
  unit_type: "count" | "minutes";
  status: "active" | "completed" | "abandoned";
  day_number: number;
  streak: number;
  today_value: number;
  today_completed: boolean;
  timer_running: boolean;
  timer_capped: boolean; // reached 6000 while running without overtime: stopped
  overtime: boolean;
  timer_started_at: string | null;
  last_activity_at: string | null;
};

// Threshold: 100 reps, or 100 minutes stored as seconds.
export const target = (g: Pick<Goal, "unit_type">) => (g.unit_type === "count" ? 100 : 6000);

export async function loadActive(supabase: SupabaseClient): Promise<Goal[]> {
  const { data } = await supabase
    .from("goal_progress")
    .select("*")
    .eq("status", "active")
    .order("start_date")
    .order("id");
  return (data ?? []) as Goal[];
}

export function fmt(g: Pick<Goal, "unit_type">, v: number) {
  if (g.unit_type === "count") return String(v);
  const m = Math.floor(v / 60);
  return `${m}:${String(v % 60).padStart(2, "0")}`;
}
