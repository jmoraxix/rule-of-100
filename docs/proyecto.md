# Project manifest — Rule of 100

> Contract file for the `/trabajo` cycle. Fixed name and location: `docs/proyecto.md`.
> The main session (orchestrator and final gate) reads this first. Everything project-specific lives
> here; the skill itself is generic.

## Identity

**Rule of 100**: a mobile-first web app for committing to one action, 100 units a day, for 100 days.

- **Owner and decision-maker:** José Mora. Reviews every PR, merges, decides product.
- **Canonical scope:** `docs/proyecto.md` §Product. Nothing outside it gets built; out-of-scope findings become new tasks.

## Sources of truth

| File | Contains |
|---|---|
| `docs/proyecto.md` §Product | Product scope, flows, data model, open questions |
| `CLAUDE.md` | Stack, commands, domain invariants |
| `docs/roadmap.md` | Task board (references only) + log |
| `docs/tareas/<ID>.md` | Permanent detail of each task, one file per PR |

## Non-negotiable invariants

Breaking any of these rejects the PR:

1. **Rules live in Postgres.** Progress changes only through SQL functions (`increment`, timer
   start/pause/resume). The client has no `UPDATE` grant on `daily_entries`. A future native client
   must be able to reuse the backend unchanged.
2. **RLS on every table.** Users see only their own rows. Every authorization change is verified with
   a negative test: a request with another user's JWT returns 0 rows or is refused.
3. **No decrement, no set-value.** No code path lowers or overwrites a counter's value.
4. **`completed_at` is set once** (first time `value` reaches the threshold) and never cleared.
5. **Day boundary = the user's timezone** (`profiles.timezone`), computed in SQL, never from the client clock.
6. **At most one running timer per user**, enforced by a partial unique index, not only in code.
7. **Monochrome UI.** The only accent is the inverted "overachieved" state above 100.

## Product principle

**One action, zero friction.** When two valid implementations exist, pick the one with fewer taps to
log progress, and the one that nudges the user toward a single goal.

## Verification commands

Defined by task `R100-T01` (scaffold). The same gates run in CI on every PR and push to `main`.

```bash
pnpm install --frozen-lockfile
pnpm typecheck
pnpm lint
pnpm build
pnpm db:start     # local Supabase (Docker); pnpm db:stop when done
pnpm test:db      # pgTAP tests in supabase/tests/ (supabase test db)
pnpm test:db supabase/tests/<file>.test.sql   # one pgTAP file
```

## Definition of done

- **Per task:** typecheck / lint / build / test:db green. Every new DB rule has a pgTAP test **and its
  mutation**: proof the test goes red if the rule is removed. UI tasks include a screenshot at phone
  width, portrait and landscape.
- **Release (MVP):** every Must in `docs/proyecto.md` §Product → Functional Requirements closed, deployed to Vercel, signed in on a real phone.

## Resource policy

- Max concurrency: **1 dev + 1 security + 1 post-merge**.
- At most one `next dev`, on port 3000, only when a task needs a browser check. Dev agents in
  worktrees verify with the gates, not a server.
- Local Supabase (Docker) is shared by all lanes. **Only one lane applies migrations at a time**; after
  each merge, reset the local DB from `main` before running gates.
- Merged worktrees and branches are cleaned up immediately.

## Task log by files

- **PRs do not edit `docs/roadmap.md`.** Each PR creates its `docs/tareas/<ID>.md` (format in
  `docs/tareas/README.md`). One file per task means no conflicts between PRs.
- After each merge, the post-merge agent sets `estado: hecha` in the task file and updates the task's
  row and log line in `docs/roadmap.md`.

## Repo tools

| Tool | Purpose |
|---|---|
| `.claude/agents/security-engineer.md` | Per-PR security review for this project (overrides the user-level HSF one) |

## Product

### 1. Overview
A minimal web app (mobile-first) that helps a user commit to one action, 100 units per day, for 100 days. Inspired by Alex Hormozi's Rule of 100. Consistency is the game: progress is measured in days completed, not volume.

### 2. Goals
- Get a user from sign-up to first tracked unit in under 60 seconds.
- Make daily completion a single, obvious action (one big button).
- Reward consistency (completed days), not raw output.
- Work from a phone on the nightstand: landscape mode shows one goal full screen.

#### Non-goals (MVP)
- Anti-cheat / server-validated timers (v2)
- Native mobile apps (web/PWA only)
- Social features (leaderboard, friends, comments, sharing)
- Notifications / reminders

### 3. Target User
Founders, creators, and salespeople who want to build output volume through a daily habit (e.g., 100 outreach messages, 100 minutes of content creation).

### 4. Core Concepts
| Term | Definition |
|---|---|
| Goal | One action the user commits to for 100 days. Several are allowed, but the app strongly recommends exactly one. |
| Unit type | `count` (repetitions) or `minutes` (time). |
| Day | Calendar day in the user's timezone, resetting at local midnight. |
| Completed day | A day where the user reached 100 units. Counts once, even if exceeded. |

### 5. User Flow

#### 5.1 Onboarding
1. Sign up / log in (Supabase Auth: email magic link or Google).
2. Define the action, e.g., "Send outreach messages" or "Create content".
3. Choose unit type: **Count** or **Minutes**.
4. Confirm. Challenge starts today (Day 1 of 100).

#### 5.2 Goal list (home)
- With one goal (the common case), home opens straight into that goal's daily screen.
- With two or more, home is a list of goals, each showing action name, Day X / 100, today's progress, and streak. Tapping one opens its daily screen.
- **Creating a second goal shows a strong warning** explaining that the Rule of 100 works by focusing on one action, and requires an explicit confirmation. The list keeps a persistent, low-key reminder while more than one goal is active.

#### 5.3 Daily screen
- Shows: action name, Day X / 100, today's progress (0–100+), streak of completed days.
- One large primary button whose behavior depends on unit type (below).

#### 5.4 Landscape / nightstand mode
- Rotating the phone to landscape shows one goal full screen: the goal whose timer is running, otherwise the last goal the user touched. Swipe left/right to switch goals.
- Counter: the whole screen is the `+1` target, with the number large in the middle. No decrement.
- Timer: elapsed time large in the middle, tap to pause/resume.
- Keeps the screen awake (Screen Wake Lock API) while in this mode.

#### 5.5 Counter mode (`count`)
- Big `+1` button. Each tap increments today's value by 1.
- No decrement. Ever.
- At 100: completion animation, day marked complete.
- Can keep going past 100. Visual state changes (e.g., inverted colors) to signal "overachieved".

#### 5.6 Timer mode (`minutes`)
- Big **Start** button. Can start once per day; afterwards shows **Pause / Resume**.
- Stores `timer_started_at` timestamp. Elapsed = accumulated time + (now − started_at) while running.
- Survives page refresh by recalculating from the stored timestamp.
- Can pause; cannot skip ahead or manually set progress.
- **Only one timer can run at a time across all of a user's goals.** Starting or resuming one while another runs is refused (the user pauses the other first).
- At 100 minutes: completion animation, day marked complete. Timer may keep running past 100 (same overachieved state).

### 6. Functional Requirements
| ID | Requirement | Priority |
|---|---|---|
| FR1 | User can sign up / log in | Must |
| FR2 | User can create goals (action + unit type); a second goal requires confirming a strong warning | Must |
| FR3 | Counter increments by 1, never decrements | Must |
| FR4 | Timer starts once/day, pauses, resumes, persists across refresh | Must |
| FR5 | Day marked complete at 100 units, only once | Must |
| FR6 | Progress >100 allowed and visually distinct | Should |
| FR7 | Completion animation at 100 | Should |
| FR8 | Landscape mode: one goal full screen, swipe between goals, screen kept awake | Must |
| FR11 | At most one running timer per user | Must |
| FR9 | Light/dark mode following system preference | Should |
| FR10 | Day boundary uses user's timezone (captured at sign-up) | Must |

### 7. Design
- Strictly monochrome: black on white (light), white on black (dark).
- One accent state only: inverted colors when >100.
- Mobile-first, thumb-reachable primary button.
- Large numeric typography for the counter/timer.
- Installable as PWA (stretch, not required for MVP).

### 8. Tech Stack
| Layer | Choice | Why |
|---|---|---|
| Frontend | Next.js (App Router) | Fast to build, native Vercel fit |
| Hosting | Vercel (free tier) | Zero-config deploy |
| Auth | Supabase Auth | Avoids extra dependency (Clerk) |
| Database | Supabase Postgres (free tier) | RLS + SQL functions hold the rules, so a future native client reuses them |
| Styling | Tailwind CSS | Monochrome theme + dark mode trivial |

### 9. Data Model

#### `profiles`
| Column | Type | Notes |
|---|---|---|
| id | uuid (PK, = auth.users.id) | |
| display_name | text | Reserved for the v2 leaderboard |
| timezone | text | IANA, e.g., `America/Costa_Rica` |
| created_at | timestamptz | |

#### `challenges`
| Column | Type | Notes |
|---|---|---|
| id | uuid (PK) | |
| user_id | uuid (FK → profiles) | |
| action | text | e.g., "Send outreach messages" |
| unit_type | enum(`count`, `minutes`) | |
| start_date | date | Local date of Day 1 |
| status | enum(`active`, `completed`, `abandoned`) | Several `active` allowed |

#### `daily_entries`
| Column | Type | Notes |
|---|---|---|
| id | uuid (PK) | |
| challenge_id | uuid (FK) | |
| user_id | uuid (FK) | |
| entry_date | date | Local date; unique with challenge_id |
| value | int | Count, or accumulated seconds for timer |
| timer_started_at | timestamptz, nullable | Set while timer running; at most one non-null per user (partial unique index) |
| completed_at | timestamptz, nullable | Set once when value hits 100 |

Row Level Security: users read only their own rows. Progress changes only through SQL functions (increment, timer start/pause/resume), never through direct `UPDATE`s from the client.

### 10. Success Metrics (MVP)
- % of new users who complete Day 1
- Day-7 retention (users with ≥5 completed days in first 7)
- Median completed days per active challenge

### 11. Out of Scope → v2
- Leaderboard by completed days
- Server-side timer validation (anti-cheat)
- Custom targets
- Reminders / push notifications
- Friends-only leaderboards, sharing completions
- Native app wrapper

### 12. Open Questions
1. Does a missed day end the challenge, or is it "100 completed days" regardless of gaps?
2. What happens after Day 100 — new challenge, badge, archive?
3. Timer: allow seconds for testing in dev only?
