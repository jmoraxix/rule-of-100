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

// Per-device settings (localStorage, in-memory fallback when storage is blocked).
const KEY = "r100-settings";
const subs = new Set<() => void>();
let mem: string | null = null;
const readRaw = () => {
  if (mem === null) {
    try {
      mem = localStorage.getItem(KEY) ?? "";
    } catch {
      mem = "";
    }
  }
  return mem;
};
const subSettings = (cb: () => void) => (subs.add(cb), () => void subs.delete(cb));
function parseSettings(raw: string) {
  try {
    const s = { ring: true, sounds: true, ...(JSON.parse(raw || "{}") as object) } as Record<string, unknown>;
    return { ring: s.ring === true, sounds: s.sounds === true };
  } catch {
    return { ring: true, sounds: true };
  }
}
function saveSettings(next: { ring: boolean; sounds: boolean }) {
  mem = JSON.stringify(next);
  try {
    localStorage.setItem(KEY, mem);
  } catch {
    // blocked storage: setting lasts until reload
  }
  subs.forEach((f) => f());
}

function beep(ctx: AudioContext, n = 3, freq = 880) {
  for (let i = 0; i < n; i++) {
    const o = ctx.createOscillator();
    const gain = ctx.createGain();
    o.frequency.value = freq;
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
  const settings = parseSettings(useSyncExternalStore(subSettings, readRaw, () => ""));
  const [showSet, setShowSet] = useState(false);
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

  // A capped timer (reached 0 without overtime) is shown stopped even before the server folds it.
  const anyRunning = goals.some((g) => g.timer_running && !g.timer_capped);
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
  const count = g.unit_type === "count";
  const ticking = g.timer_running && !g.timer_capped;
  const raw = count ? g.today_value + pending : g.today_value + (ticking ? Math.max(0, Math.floor((now - g.at) / 1000)) : 0);
  // Without overtime the server stops the timer at 6000 s (00:00); mirror that locally.
  const value = count || g.overtime ? raw : Math.min(6000, raw);
  const running = ticking && (g.overtime || value < 6000);
  const fresh = g.today_value === 0 && !g.timer_running;
  // Local clock hit 0 but the server hasn't said so yet (clock skew): wait for it, don't offer overtime.
  const waiting = !count && !g.overtime && ticking && raw >= 6000;
  const done = value >= target(g) || g.today_completed;
  const over = value > target(g);
  const shown = g.unit_type === "count" ? String(value) : clock(value);

  useEffect(() => {
    if (!waiting) return;
    const i = setInterval(() => void refresh(), 1000); // ponytail: polls until the server confirms
    return () => clearInterval(i);
  }, [waiting, refresh]);

  // Beep once when a running timer crosses 0 on screen. Loading past 0 stays silent
  // (prevVal starts at the loaded value). ponytail: silent when locked or backgrounded.
  const audio = useRef<AudioContext | null>(null);
  const prevVal = useRef({ id: g.id, v: value });
  useEffect(() => {
    const p = prevVal.current;
    prevVal.current = { id: g.id, v: value };
    if (g.unit_type !== "minutes" || p.id !== g.id || !audio.current || !settings.sounds) return;
    if (p.v < 6000 && value >= 6000) beep(audio.current);
    else if (p.v < 3000 && value >= 3000) beep(audio.current, 1, 520); // 50%: one lower beep
  }, [g.id, g.unit_type, value, settings.sounds]);

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
    // timer_resume at 6000 is "Start overtime" (the server sets overtime).
    const fn = running ? "timer_pause" : fresh ? "timer_start" : "timer_resume";
    let { error } = await supabase.rpc(fn, { p_challenge: g.id });
    if (error?.message.includes("already running")) {
      await refresh(); // stale view: re-sync, then retry once
      ({ error } = await supabase.rpc(fn, { p_challenge: g.id }));
    }
    if (error) setError(error.message);
    await refresh();
    setBusy(false);
  }

  const timerLabel = running ? "Pause" : waiting ? "Syncing…" : !g.overtime && value >= 6000 ? "Start overtime" : fresh ? "Start" : "Resume";
  const state = over ? "Overachieved" : done ? "Complete" : "";
  const shell = `${over ? "over" : ""} bg-background text-foreground`;
  const numeral = `num complete-num font-semibold leading-none ${pop ? "" : "[animation:none]"}`;
  const ringOn = settings.ring;
  // One fixed slot for Start / Pause / Resume / Start overtime: same size, so nothing shifts.
  const control = (cls: string) =>
    !count && (
      <button type="button" onClick={() => void toggle()} disabled={busy || waiting} className={`btn h-12 whitespace-nowrap px-2 ${cls}`}>
        {timerLabel}
      </button>
    );
  // box sizes the ring with min(vw, vh) so it always fits the viewport.
  const ring = (box: string, text: string, ctl: string) => (
    <div className={`relative grid shrink-0 aspect-square place-items-center ${ringOn ? box : ""}`}>
      {ringOn && (
        <svg viewBox="0 0 100 100" className="absolute inset-0 h-full w-full -rotate-90" aria-hidden="true">
          <circle cx="50" cy="50" r="48" fill="none" stroke="var(--line)" strokeWidth="1.5" />
          <circle
            cx="50"
            cy="50"
            r="48"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            pathLength={100}
            strokeDasharray={100}
            strokeDashoffset={100 - Math.min(100, (value / target(g)) * 100)}
            className="motion-safe:transition-[stroke-dashoffset] motion-safe:duration-500"
          />
        </svg>
      )}
      <div className="relative flex flex-col items-center gap-[min(2vw,2vh)]">
        <p
          className={`${numeral} ${text}`}
          role={count ? undefined : "timer"}
          aria-live={count ? "polite" : undefined}
          aria-label={count ? `${value} today` : undefined}
        >
          {shown}
        </p>
        {control(ctl)}
      </div>
    </div>
  );
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
        {ring(
          "w-[min(80vh,50vw)]",
          ringOn ? (count ? "text-[min(26vh,16vw)]" : "text-[min(14vh,8vw)]") : count ? "text-[min(52vh,32vw)]" : "text-[min(40vh,22vw)]",
          "w-[min(44vh,11rem)] text-[clamp(0.875rem,4vh,1.125rem)]",
        )}
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
          </div>
        )}
      </div>
    );
  }

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
          <button type="button" className="link" aria-expanded={showSet} onClick={() => setShowSet((v) => !v)}>
            Settings
          </button>
          <SignOut />
        </nav>
      </header>
      {showSet && (
        <div className="mt-3 flex flex-col border border-line px-4">
          {(["ring", "sounds"] as const).map((k) => (
            <label key={k} className="flex min-h-11 items-center justify-between gap-4">
              {k === "ring" ? "Progress ring" : "Sounds"}
              <input
                type="checkbox"
                className="size-6 accent-foreground"
                checked={settings[k]}
                onChange={(e) => saveSettings({ ...settings, [k]: e.target.checked })}
              />
            </label>
          ))}
        </div>
      )}
      <section className="flex flex-1 flex-col items-center justify-center gap-4 text-center">
        <div className="flex w-full items-center justify-center gap-4">
          {ring(
            count ? "w-[min(62vw,46vh)]" : "w-[min(84vw,52vh)]",
            ringOn ? (count ? "text-[min(18vw,13vh)]" : "text-[min(13vw,7vh)]") : count ? "text-[clamp(5rem,30vw,14rem)]" : "text-[clamp(4rem,22vw,10rem)]",
            "w-[min(46vw,11rem)] text-[clamp(0.875rem,4vw,1.125rem)]",
          )}
          {count && (
            <button
              type="button"
              onClick={tap}
              aria-label="Add 1"
              className="btn aspect-square h-[min(18vw,11vh)] text-[min(12vw,8vh)] leading-none"
            >
              +
            </button>
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
    </main>
  );
}
