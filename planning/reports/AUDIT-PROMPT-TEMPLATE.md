# Reusable external-audit prompt (Talaria-27)

Written 2026-08-07 after two external audits landed the same day. The
gpt-sol-xhigh audit found what became **#285** (a confirmed P1 our own
1797-test suite structurally could not express); the momentum report was
accurate on facts but wrong on one recommendation and cited an event that
does not exist on our wire. **2 of ~10 external claims needed correction** —
which is why the validation clause below is non-negotiable.

**Venue:** a fresh session pointed at `main` (cloud preferred — it cannot
touch local worktrees or the live Hermes install). For a single PR, use
`/code-review ultra <PR#>` instead; it is purpose-built and needs no prompt.

**Sequence:** merge outstanding PRs first, or the newest code is invisible.

---

## The prompt — paste from here

You are performing an independent, adversarial audit of a real iOS codebase
that is close to shipping. Be ruthless about correctness and honest about
uncertainty. A finding you cannot ground in specific code is worse than no
finding — it costs the maintainer more to disprove than it would have cost
you to omit.

**Read these first, in this order, before forming any opinion:**
1. `CLAUDE.md` — standing rules, and a list of traps that have already cost
   days. Several plausible-looking "fixes" in this codebase are FALSIFIED
   and documented there.
2. `OPEN_ITEMS.md` (live board) and `OPEN_ITEMS-ARCHIVE.md` (closed, verbatim
   history). One numbering sequence spans both.

**Do not re-litigate anything those files mark settled.** In particular, do
not propose: narrowing ATS to `NSAllowsLocalNetworking` (a four-arm
experiment falsified it); hardening the relay or connector (standing rule —
their direction is deletion); anything attributed to "#24f" (dead). If you
believe a settled decision is wrong, say so in one paragraph in a separate
section, with new evidence — do not smuggle it in as a finding.

**Scope — audit these, in priority order:**
1. Code written and reviewed within a single session (highest risk of shared
   blind spots): the runs-plane transport in
   `Talaria/Services/Live/SessionsHermesClient*.swift`.
2. The high-churn reconciliation seam: `Talaria/Stores/ChatStore.swift`,
   especially anything named merge/adopt/reconcile/claim/dedupe.
3. Concurrency and lifecycle across `Talaria/Stores/AppContainer.swift` and
   the services it owns — ownership, cancellation, and state written after
   an `await`.
4. Anything else only if you have budget left. Do not attempt a shallow
   sweep of everything; depth on (1)–(3) beats breadth.

**Evidence contract — every finding must carry all five:**
- `file:line` for the actual code, quoted.
- A **concrete failure scenario**: specific inputs or interleaving → the
  wrong result. Not "could be unsafe."
- A label: **STATIC** (read-only reasoning) or **REPRODUCED** (you ran it).
  Never blur these.
- **What would DISPROVE it** — the observation that would show you wrong.
- A severity, calibrated: **Critical** = data loss, credential leak, or
  crash on a common path; **Important** = wrong behavior a user would hit;
  **Minor** = polish. Most findings are Minor. Say so.

**Hard rules:**
- Search BOTH tracker files before reporting anything; if it is already
  filed, say "already tracked as #N" and move on. Do not re-file.
- **Do not change any code. Do not open PRs or issues.** Report only.
- Cap yourself at **10 findings**, ranked. If you have more, the ranking is
  the valuable part — a list of 40 is a list nobody acts on.
- Include a section titled **"What I checked and found clean"** naming the
  areas you examined without finding anything. Negative space is genuinely
  useful and it tells the maintainer where NOT to re-audit.
- If you are uncertain, say the number: "I am ~60% on this." Confident wrong
  findings are the expensive failure mode here.

**Then finish with:**
- Your **top 3 by expected harm**, with reasoning — not by how interesting
  they were to find.
- One paragraph: **what this codebase does well**, specifically. It
  calibrates the rest of your report and it is genuinely informative.

## Paste to here

---

## After it returns — do not skip this

Today's lesson: **validate before filing.** For every finding, check the
claim against the actual code before it enters the tracker. Two of ten
external claims were wrong in ways that would have misled us, and one
reproduced as a RACE rather than a certainty (it passed on run 1 and failed
on run 2 — only repeated runs caught it). A false claim in the tracker costs
more than a missed finding.
