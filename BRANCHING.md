# Talaria — Branching & Session Protocol

Hard-won rules from the 2026-07-02 lineage-divergence incident, where local `main` and
`origin/main` silently forked and evolved *parallel, different* implementations of the same
open items (#35/#41/#24a) for days. Cost a full session to untangle. Don't repeat it.

## The one rule that matters

**`origin/main` is the single source of truth. Always.**
Local `main` is a disposable mirror of it — never a place where unique work accumulates
unpushed. If local `main` is ever "ahead of origin", push it *that session* or you're
re-forking history.

## Start every session with this (non-negotiable)

```sh
cd /Users/owenjones/Documents/Claude/Talaria
git fetch origin
git status                                   # working-tree state
git rev-list --left-right --count main...origin/main   # want "0<TAB>0"
```

- `0  0` → in sync, proceed.
- `N  0` (local ahead) → **stop.** Unpushed local commits exist. Push them or understand why
  they're there before doing anything else.
- `0  N` (behind) → `git pull --ff-only` before starting.
- `N  M` (**diverged**) → **STOP. Do not commit, do not build-and-merge.** This is the
  incident state. Reconcile deliberately (see below) before any new work.

## Feature work

- Branch from **up-to-date `origin/main`**: `git switch -c feat/thing origin/main`.
- One lineage per item. If two sessions might touch the same item, coordinate — do NOT let
  both commit competing implementations to `main`-equivalents.
- Merge to `main` via PR on GitHub (like PR #1) OR fast-forward locally + push. Either way,
  **push immediately** so `origin/main` is current.
- Parallel Claude sessions are common here. Each MUST fetch+divergence-check first, and must
  never assume its local `main` reflects reality.

## Reconciling a divergence (if it happens anyway)

1. **Tag both tips first**: `git tag prereconcile/local-main-YYYYMMDD main`. Nothing is lost
   with a tag.
2. Pick canonical (default: `origin/main` — it's the published/tested one).
3. `git switch -c reconcile/merge-lineages origin/main`.
4. Cherry-pick ONLY the genuinely-unique commits from the other lineage; drop redundant
   re-implementations of items the canonical side already has.
5. Resolve conflicts by keeping the *verified-on-device* version.
6. Build-verify on device, THEN reset `main` to the reconcile branch and push.

## Gotchas (bit us for real)

- **`xcodegen generate` strips `aps-environment`** from `Talaria.entitlements` — it regenerates
  entitlements from `project.yml`, which doesn't declare the push entitlement. After any bare
  `xcodegen`, check `grep aps-environment Talaria/Talaria.entitlements` before deploying, or the
  #44 notifications fix silently regresses. (Real fix: declare it in `project.yml`.)
- **`xcodegen generate` is still mandatory** when adding/removing Swift files (sources are listed
  explicitly) — just verify entitlements survived.
- **Stale local `origin/main` cache**: if the Mac hasn't fetched in days, all `git log origin/main`
  / ancestry checks lie. `git fetch` FIRST, always, before trusting any comparison.
- **Xcode "Use Version on Disk vs Keep Xcode Version"** after a branch switch/reset: **always
  choose disk** — disk is the git truth; "keep Xcode" reintroduces stale in-memory state.

## Safety-net habits

- **Every few sessions (and before merging a wave): run `tools/orphan-audit.sh`** and review the
  built-but-unreferenced surfaces it flags (the dead-Inbox class of bug — GitHub #49); refresh the
  committed `tools/orphan-audit-report.md` if it drifted. It's a review list, never a delete list.
- Tag before any `reset --hard` on a branch that has unpushed commits.
- Session scratch/handoffs go in `handoffs/` (gitignored) — never commit them.
- `OPEN_ITEMS.md`: Claude edits + verifies; Owen commits (unless he says otherwise in-session).
  Always re-check the max item number against the *live* file before appending (parallel
  sessions advance numbering independently).
