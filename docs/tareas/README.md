# `docs/tareas/` — permanent detail of each task

Each PR creates **one** file here: `docs/tareas/<ID>.md` (e.g. `R100-T03.md`). Files are never
deleted. The roadmap only links to them, so it stays short.

## Format

```markdown
---
id: R100-T03
titulo: "SQL functions for progress"
estado: pr-abierto
pr: 7
fecha: 2026-10-06
rama: feat/t03-progress-functions
---

What was done, the decisions (with the reason for each), and how it was verified
(commands + output).
```

- `estado`: `pr-abierto` | `hecha`. The post-merge agent sets `hecha`.
- `pr`: PR number (optional until the PR exists).
- `fecha`: `YYYY-MM-DD`.
