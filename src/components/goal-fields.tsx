"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// Action + unit picker; the only write is the create_challenge RPC.
export default function GoalForm({ confirmFirst }: { confirmFirst?: boolean }) {
  const router = useRouter();
  const [action, setAction] = useState("");
  const [unit, setUnit] = useState<"count" | "minutes">("count");
  const [ok, setOk] = useState(!confirmFirst);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!ok) return;
    setBusy(true);
    setError("");
    const { data, error } = await createClient().rpc("create_challenge", {
      p_action: action.trim(),
      p_unit: unit,
    });
    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }
    router.replace(`/goals/${(data as { id: string }).id}`);
    router.refresh();
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-6">
      {confirmFirst && (
        <section role="alert" className="border-2 border-foreground p-4">
          <h2 className="text-lg font-semibold">Think twice before adding a second goal</h2>
          <p className="mt-2 text-[clamp(1rem,3.6vw,1.375rem)]">
            The Rule of 100 works because one action gets all of your attention. Every extra goal splits
            your effort and makes it likelier that all of them stall. Finish the first one, or keep this
            for later.
          </p>
          <label className="mt-4 flex min-h-[44px] items-center gap-3 text-[clamp(1rem,3.6vw,1.375rem)] font-medium">
            <input
              type="checkbox"
              checked={ok}
              onChange={(e) => setOk(e.target.checked)}
              className="size-6 accent-current"
            />
            I understand and still want a second goal
          </label>
        </section>
      )}
      <div className="flex flex-col gap-2">
        <label htmlFor="action" className="text-[clamp(1rem,3.6vw,1.375rem)] font-medium">
          Action
        </label>
        <input
          id="action"
          required
          maxLength={120}
          value={action}
          onChange={(e) => setAction(e.target.value)}
          placeholder="Send outreach messages"
          className="field"
        />
      </div>
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-2 text-[clamp(1rem,3.6vw,1.375rem)] font-medium">Count it as</legend>
        <div className="grid grid-cols-2 gap-3">
          {(["count", "minutes"] as const).map((u) => (
            <label
              key={u}
              className={`flex min-h-[56px] cursor-pointer items-center justify-center rounded-md border border-foreground font-semibold has-[:focus-visible]:outline-3 ${
                unit === u ? "bg-foreground text-background" : ""
              }`}
            >
              <input
                type="radio"
                name="unit"
                value={u}
                checked={unit === u}
                onChange={() => setUnit(u)}
                className="sr-only"
              />
              {u === "count" ? "Count" : "Minutes"}
            </label>
          ))}
        </div>
      </fieldset>
      {error && (
        <p role="alert" className="text-[clamp(1rem,3.6vw,1.375rem)]">
          {error}
        </p>
      )}
      <button type="submit" className="btn" disabled={busy || !ok || !action.trim()}>
        {busy ? "Creating" : "Start Day 1"}
      </button>
    </form>
  );
}
