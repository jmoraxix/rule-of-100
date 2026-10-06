# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Commands

Scope is `docs/proyecto.md` §Product. Next.js 16 (App Router, `src/`), pnpm.

```bash
pnpm install --frozen-lockfile
pnpm dev                 # next dev on :3000 (only when a task needs a browser check)
pnpm typecheck           # tsc --noEmit
pnpm lint                # eslint
pnpm build               # next build
pnpm db:start            # local Supabase (Docker); db:stop when done
pnpm db:reset            # re-apply supabase/migrations/ + seed
pnpm test:db             # all pgTAP tests in supabase/tests/
pnpm test:db supabase/tests/smoke.test.sql   # a single pgTAP file
```

CI (`.github/workflows/ci.yml`) runs install, typecheck, lint, build and `test:db` on every PR and
push to `main`. Docker is shared with other projects: before `db:start`, check
`docker ps --format '{{.Names}} {{.Ports}}'` for clashes on 54320–54329 and never stop containers
you didn't start.

## How work happens

Work runs through the `/trabajo` cycle. `docs/proyecto.md` is its contract (invariants, gates,
definition of done, resource policy) and `docs/roadmap.md` is the board. Each PR adds
`docs/tareas/<ID>.md` and does **not** edit the roadmap. The owner merges; agents never do.

## Planned stack

Next.js (App Router) on Vercel · Supabase Auth (magic link + Google) · Supabase Postgres with local
dev via the Supabase CLI, migrations in `supabase/migrations/`, pgTAP tests · Tailwind CSS · pnpm.

## Architecture: the backend is the rules

Business rules live in Postgres (RLS + SQL functions), not in Next.js. The client reads its own rows
and calls functions; it cannot `UPDATE` progress directly. This is what keeps a later native (Expo)
client cheap: it reuses the same functions unchanged. Don't put progress logic in Server Actions.

Domain mechanics that span DB and UI:

- **Goals:** a user may have several active challenges, but the UI strongly discourages more than one
  (warning plus confirmation on the second). With one goal, home opens straight into it.
- **Day** = calendar day in `profiles.timezone`; `daily_entries` is unique on `(challenge_id, entry_date)`.
- **Counter (`count`)**: `+1` only. No decrement, no set-value, anywhere (including landscape mode).
- **Timer (`minutes`)**: `value` is accumulated **seconds**. While running, `timer_started_at` is set;
  elapsed = `value + (now() − timer_started_at)`. Pause folds the span into `value` and clears the
  timestamp. Start once per day, then only pause/resume. At most one running timer per user
  (partial unique index on `user_id` where `timer_started_at is not null`). The UI recomputes from
  the stored timestamp, so a refresh never loses time.
- **Completion:** threshold 100 count or 6000 seconds. `completed_at` is set once, never cleared.
  Above 100 is allowed and shown as the inverted "overachieved" state.
- **Landscape / nightstand mode:** one goal full screen (running timer, else last touched), swipe
  between goals, Screen Wake Lock on.

## Design

Strictly monochrome, light/dark following system. The only accent is inverted colors above 100.
Mobile-first, one large thumb-reachable button, large numerals.

## Out of MVP

Leaderboard, anti-cheat timers, custom targets, notifications, social features, native app. Don't
build them speculatively. Open product questions are in `docs/proyecto.md` §Product → Open Questions; ask before deciding them.
