"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function Login({ linkError }: { linkError: boolean }) {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent">("idle");
  const [error, setError] = useState(
    linkError ? "That link expired or was already used. Request a new one." : "",
  );

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setState("sending");
    setError("");
    const { error } = await createClient().auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${location.origin}/auth/callback` },
    });
    if (error) {
      setError(error.message);
      setState("idle");
    } else setState("sent");
  }

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-10 px-6">
      <header>
        <p className="num text-8xl font-semibold leading-none">100</p>
        <h1 className="mt-4 text-lg font-medium">Rule of 100</h1>
        <p className="mt-1 text-muted">One action. 100 a day. 100 days.</p>
      </header>
      {state === "sent" ? (
        <p role="status" className="text-lg">
          Check your email for the sign-in link.
        </p>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-3">
          <label htmlFor="email" className="text-sm font-medium">
            Email
          </label>
          <input
            id="email"
            type="email"
            required
            autoComplete="email"
            autoFocus
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="field"
          />
          {error && (
            <p role="alert" className="text-sm">
              {error}
            </p>
          )}
          <button type="submit" disabled={state === "sending"} className="btn">
            {state === "sending" ? "Sending" : "Send sign-in link"}
          </button>
        </form>
      )}
    </main>
  );
}
