# Project manifest — Rule of 100

> Contract file for the `/trabajo` cycle. Fixed name and location: `docs/proyecto.md`.
> The main session (orchestrator and final gate) reads this first. Everything project-specific lives
> here; the skill itself is generic.

## Identity

**Rule of 100**: a mobile-first web app for committing to one action, 100 units a day, for 100 days.

- **Owner and decision-maker:** José Mora. Reviews every PR, merges, decides product.
- **Canonical scope:** `prd.md`. Nothing outside it gets built; out-of-scope findings become new tasks.

## Sources of truth

| File | Contains |
|---|---|
| `prd.md` | Product scope, flows, data model, open questions |
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

Defined by task `R100-T01` (scaffold). Until then there are no gates. Planned:

```bash
pnpm install --frozen-lockfile
pnpm typecheck
pnpm lint
pnpm build
pnpm test:db      # pgTAP tests against local Supabase (supabase test db)
```

## Definition of done

- **Per task:** typecheck / lint / build / test:db green. Every new DB rule has a pgTAP test **and its
  mutation**: proof the test goes red if the rule is removed. UI tasks include a screenshot at phone
  width, portrait and landscape.
- **Release (MVP):** every Must in `prd.md` §6 closed, deployed to Vercel, signed in on a real phone.

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
