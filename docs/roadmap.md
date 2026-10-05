# Roadmap — Rule of 100 MVP

> The board holds **references only**: one line per task, detail in `docs/tareas/<ID>.md`.
> Statuses: `pendiente` · `pr-abierto` · `hecha` · `bloqueada`.

## Board

| ID | Task | Phase | Depends on | Status | PR |
|---|---|---|---|---|---|
| `R100-T01` | Scaffold: Next.js (App Router) + TS strict + Tailwind + pnpm, Supabase local (`supabase init`), CI running the gates, Vercel project | 0 | — | pendiente | |
| `R100-T02` | Schema + RLS: `profiles`, `challenges`, `daily_entries`, constraints (unique entry per day, one running timer per user), pgTAP tests | 1 | T01 | pendiente | |
| `R100-T03` | SQL functions: `increment`, `timer_start` / `timer_pause` / `timer_resume`, local-date from `profiles.timezone`, `completed_at` once, streak / day-number view | 1 | T02 | pendiente | |
| `R100-T04` | Auth (magic link + Google) + onboarding: capture timezone, create first goal | 2 | T03 | pendiente | |
| `R100-T05` | Goal list + create goal, with the strong warning on a second goal | 2 | T04 | pendiente | |
| `R100-T06` | Daily screen, counter mode (`+1`, overachieved state) | 3 | T05 | pendiente | |
| `R100-T07` | Daily screen, timer mode (start once, pause/resume, survives refresh, one running timer) | 3 | T05 | pendiente | |
| `R100-T08` | Landscape / nightstand mode: full-screen goal, swipe between goals, Wake Lock | 4 | T06, T07 | pendiente | |
| `R100-T09` | Completion animation + light/dark following system | 4 | T06 | pendiente | |

## Open questions (block nothing above yet; `docs/proyecto.md` §Product → Open Questions)

1. Does a missed day end the challenge, or is it 100 completed days regardless of gaps? **Affects T03 (streak and status logic).**
2. What happens after Day 100?
3. Seconds-based timer in dev for testing?

## Log

<!-- Newest first: `- YYYY-MM-DD · [ID](tareas/ID.md) — title · #PR` -->
