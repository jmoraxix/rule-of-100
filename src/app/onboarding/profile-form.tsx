"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function ProfileForm() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    const supabase = createClient();
    const { data } = await supabase.auth.getUser();
    const { error } = await supabase
      .from("profiles")
      .insert({ id: data.user!.id, display_name: name.trim(), timezone });
    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }
    router.refresh();
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-4">
      <label htmlFor="name" className="text-sm font-medium">
        Display name
      </label>
      <input
        id="name"
        required
        maxLength={50}
        autoFocus
        autoComplete="given-name"
        value={name}
        onChange={(e) => setName(e.target.value)}
        className="field"
      />
      <p className="text-sm text-muted">
        Your days follow this timezone: <span className="font-medium text-foreground">{timezone}</span>
      </p>
      {error && (
        <p role="alert" className="text-sm">
          {error}
        </p>
      )}
      <button className="btn" disabled={busy || !name.trim()}>
        Continue
      </button>
    </form>
  );
}
