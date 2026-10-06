"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { createClient } from "@/lib/supabase/client";
import { loadActive, target, type Goal } from "@/lib/goals";
import SignOut from "./sign-out";

type G = Goal & { at: number }; // at = client time the server value was read

const LANDSCAPE = "(orientation: landscape) and (max-height: 500px)";
const subscribe = (cb: () => void) => {
  const m = matchMedia(LANDSCAPE);
  m.addEventListener("change", cb);
  return () => m.removeEventListener("change", cb);
};
const useLandscape = () =>
  useSyncExternalStore(subscribe, () => matchMedia(LANDSCAPE).matches, () => false);

// Minutes goals count down from 100:00; past zero it counts up as +MM:SS.
const clock = (v: number) => {
  const r = Math.abs(6000 - v);
  return `${v > 6000 ? "+" : ""}${String(Math.floor(r / 60)).padStart(2, "0")}:${String(r % 60).padStart(2, "0")}`;
};

function beep(ctx: AudioContext) {
  for (let i = 0; i < 3; i++) {
    const o = ctx.createOscillator();
    const gain = ctx.createGain();
    o.frequency.value = 880;
    gain.gain.value = 0.2;
    o.connect(gain).connect(ctx.destination);
    const t = ctx.currentTime + i * 0.4;
    o.start(t);
    o.stop(t + 0.2);
  }
}

function pickLanding(goals: G[]) {
  const running = goals.find((g) => g.timer_running);
  if (running) return running.id;
  return [...goals].sort((a, b) => (b.last_activity_at ?? "").localeCompare(a.last_activity_at ?? ""))[0].id;
}

export default function Daily({ initial, initialId }: { initial: Goal[]; initialId: string }) {
  const [supabase] = useState(createClient);
  const [t0] = useState(() => Date.now());
  const [now, setNow] = useState(t0);
  const [goals, setGoals] = useState<G[]>(() => initial.map((g) => ({ ...g, at: t0 })));
  const [activeId, setActiveId] = useState(initialId);
  const [pending, setPending] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const landscape = useLandscape();
  const queue = useRef<Promise<void>>(Promise.resolve());
  const inflight = useRef(0);
  const swiped = useRef(false);
  const startPt = useRef<[number, number]>([0, 0]);

  const refresh = useCallback(async () => {
    const list = await loadActive(supabase);
    if (list.length === 0) return;
    const at = Date.now();
    setNow(at);
    setGoals(list.map((g) => ({ ...g, at })));
    setActiveId((id) => (list.some((g) => g.id === id) ? id : list[0].id));
  }, [supabase]);

  // Server stays the truth: re-sync whenever the tab comes back.
  useEffect(() => {
    const sync = () => document.visibilityState === "visible" && void refresh();
    document.addEventListener("visibilitychange", sync);
    window.addEventListener("focus", sync);
    return () => {
      document.removeEventListener("visibilitychange", sync);
      window.removeEventListener("focus", sync);
    };
  }, [refresh]);

  const anyRunning = goals.some((g) => g.timer_running);
  useEffect(() => {
    if (!anyRunning) return;
    const i = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(i);
  }, [anyRunning]);

  // Screen Wake Lock while in landscape.
  useEffect(() => {
    if (!landscape || !("wakeLock" in navigator)) return;
    let lock: WakeLockSentinel | null = null;
    let alive = true;
    const acquire = async () => {
      try {
        if (document.visibilityState === "visible") {
          lock = await navigator.wakeLock.request("screen");
          if (!alive) void lock.release();
        }
      } catch {
        // denied (e.g. low battery): the screen may sleep, nothing else breaks
      }
    };
    void acquire();
    document.addEventListener("visibilitychange", acquire);
    return () => {
      alive = false;
      document.removeEventListener("visibilitychange", acquire);
      void lock?.release();
    };
  }, [landscape]);

  // Entering landscape: jump to the running goal, else the last touched.
  const [prevLand, setPrevLand] = useState(landscape);
  if (prevLand !== landscape) {
    setPrevLand(landscape);
    if (landscape) setActiveId(pickLanding(goals));
  }

  const idx = Math.max(0, goals.findIndex((g) => g.id === activeId));
  const g = goals[idx];
  const value =
    g.unit_type === "count"
      ? g.today_value + pending
      : g.today_value + (g.timer_running ? Math.max(0, Math.floor((now - g.at) / 1000)) : 0);
  const done = value >= target(g) || g.today_completed;
  const over = value > target(g);
  const shown = g.unit_type === "count" ? String(value) : clock(value);

  // Beep once when a running timer crosses 0 on screen. Loading past 0 stays silent
  // (prevVal starts at the loaded value). ponytail: silent when locked or backgrounded.
  const audio = useRef<AudioContext | null>(null);
  const prevVal = useRef({ id: g.id, v: value });
  useEffect(() => {
    const p = prevVal.current;
    prevVal.current = { id: g.id, v: value };
    if (g.unit_type === "minutes" && p.id === g.id && p.v < 6000 && value >= 6000 && audio.current) beep(audio.current);
  }, [g.id, g.unit_type, value]);

  // Completion pop: only when this goal flips to done while on screen.
  const [prev, setPrev] = useState({ id: g.id, done });
  const [pop, setPop] = useState(false);
  if (prev.id !== g.id || prev.done !== done) {
    setPrev({ id: g.id, done });
    setPop(prev.id === g.id && done);
  }

  function tap() {
    setError("");
    setPending((p) => p + 1);
    inflight.current += 1;
    const id = g.id;
    queue.current = queue.current.then(async () => {
      const { data, error } = await supabase.rpc("increment", { p_challenge: id });
      if (error) setError(error.message);
      else
        setGoals((list) =>
          list.map((x) => (x.id === id ? { ...x, today_value: (data as { value: number }).value } : x)),
        );
      setPending((p) => p - 1); // success or rollback
      inflight.current -= 1;
      if (inflight.current === 0) await refresh();
    });
  }

  async function toggle() {
    if (busy) return;
    setBusy(true);
    setError("");
    // Needs a user gesture: create/resume the AudioContext on Start/Resume.
    audio.current ??= new AudioContext();
    void audio.current.resume();
    const fn = g.timer_running ? "timer_pause" : g.today_value === 0 ? "timer_start" : "timer_resume";
    const { error } = await supabase.rpc(fn, { p_challenge: g.id });
    if (error) setError(error.message);
    await refresh();
    setBusy(false);
  }

  const count = g.unit_type === "count";
  const running = g.timer_running;
  const timerLabel = running ? "Pause" : g.today_value === 0 ? "Start" : "Resume";
  const state = over ? "Overachieved" : done ? "Complete" : "";
  const shell = `${over ? "over" : ""} bg-background text-foreground`;
  const numeral = `num complete-num font-semibold leading-none ${pop ? "" : "[animation:none]"}`;
  const sub = "text-muted text-[clamp(1.125rem,min(3.6vw,3.6vh),1.875rem)]";

  if (landscape) {
    const swipe = {
      onPointerDown: (e: React.PointerEvent) => (startPt.current = [e.clientX, e.clientY]),
      onPointerUp: (e: React.PointerEvent) => {
        const dx = e.clientX - startPt.current[0];
        const dy = e.clientY - startPt.current[1];
        if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy)) {
          swiped.current = true;
          const next = idx + (dx < 0 ? 1 : -1);
          if (goals[next]) setActiveId(goals[next].id);
        }
      },
    };
    const body = (
      <>
        <span className="absolute left-6 top-4 text-left text-[clamp(1.5rem,7vh,3rem)] font-medium">
          {g.action}
          <span className={`block ${sub}`}>
            Day {g.day_number}/100 · streak {g.streak}
          </span>
        </span>
        <span
          className={`${numeral} text-[min(52vh,32vw)]`}
          role={count ? undefined : "timer"}
          aria-live={count ? "polite" : undefined}
        >
          {shown}
        </span>
        <span className={`absolute bottom-4 left-6 ${sub}`}>
          {error || state}
          {goals.length > 1 && ` ${idx + 1} of ${goals.length}`}
        </span>
      </>
    );
    return (
      <div className={`${shell} fixed inset-0`}>
        {count ? (
          <button
            type="button"
            aria-label={`Add one to ${g.action}`}
            className={`${pop ? "complete-ring" : ""} relative flex h-full w-full touch-pan-y select-none flex-col items-center justify-center`}
            {...swipe}
            onClick={() => {
              if (swiped.current) swiped.current = false;
              else tap();
            }}
          >
            {body}
          </button>
        ) : (
          <div
            className={`${pop ? "complete-ring" : ""} relative flex h-full w-full touch-pan-y select-none flex-col items-center justify-center`}
            {...swipe}
          >
            {body}
            <button
              type="button"
              onClick={() => void toggle()}
              disabled={busy}
              className="btn absolute bottom-4 right-6 h-[clamp(4rem,18vh,6rem)] px-8 text-[clamp(1.5rem,7vh,2.5rem)]"
            >
              {timerLabel}
            </button>
          </div>
        )}
      </div>
    );
  }

  const big = "btn h-[clamp(6rem,26vw,10rem)]";
  return (
    <main className={`${shell} relative flex min-h-dvh flex-col px-6 pb-8 pt-6 ${pop ? "complete-ring" : ""}`}>
      <header className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-[clamp(1.75rem,7vw,3rem)] font-semibold leading-tight tracking-tight">{g.action}</h1>
          <p className={sub}>
            Day {g.day_number}/100 · streak {g.streak}
          </p>
        </div>
        <nav className="flex items-center gap-4 text-[clamp(1rem,3.4vw,1.5rem)]">
          {goals.length > 1 && (
            <Link href="/" className="link">
              Goals
            </Link>
          )}
          <Link href="/new" className="link">
            New goal
          </Link>
          <SignOut />
        </nav>
      </header>
      <section className="flex flex-1 flex-col items-center justify-center gap-4 text-center">
        <div className="flex w-full items-center justify-center gap-4">
          <p
            className={`${numeral} ${count ? "text-[clamp(5rem,30vw,14rem)]" : "text-[clamp(4rem,22vw,10rem)]"}`}
            role={count ? undefined : "timer"}
            aria-live={count ? "polite" : undefined}
            aria-label={count ? `${value} today` : undefined}
          >
            {shown}
          </p>
          {count ? (
            <button type="button" onClick={tap} aria-label="Add one" className={`${big} min-w-[34vw] px-4 text-[clamp(2.5rem,12vw,5rem)]`}>
              +1
            </button>
          ) : (
            running && (
              <button type="button" onClick={() => void toggle()} disabled={busy} className={`${big} px-6 text-[clamp(1.5rem,7vw,3rem)]`}>
                Pause
              </button>
            )
          )}
        </div>
        <p className={`min-h-8 font-medium uppercase tracking-widest ${sub}`} aria-live="polite">
          {state}
        </p>
      </section>
      {error && (
        <p role="alert" className={`mb-3 text-center ${sub}`}>
          {error}
        </p>
      )}
      {!count && !running && (
        <button type="button" onClick={() => void toggle()} disabled={busy} className={`${big} w-full`}>
          {timerLabel}
        </button>
      )}
    </main>
  );
}
