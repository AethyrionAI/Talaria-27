# OPUS T27 — the archive pass (docs-only, no code)

> ## ⚠️ AMENDED 2026-08-09 — THE CANDIDATE SET NEARLY DOUBLED AFTER THIS WAS WRITTEN
>
> The free-wins sweep (commit `231f973`) **closed eight more items in place**
> after this dispatch was drafted. They are closed-in-place, so they are still
> in `OPEN_ITEMS.md` and are now MOVE candidates for this sweep:
>
> **#80** (superseded by #251 2A) · **#81** (removed by #238) · **#130** (Owen
> closed it 2026-07-31) · **#149** (already satisfied) · **#161** (a
> never-actioned close from 2026-08-01) · **#187** (absent from the handler,
> upstream) · **#242** (delivered as #251 2A) · **#256** (shipped 2026-08-05).
>
> **Plus the original eight**, unchanged: #78, #285, #286, #295, #291, #294,
> #273, #284. **So ~14 MOVE candidates, not 6** — re-run Step 1's residue check
> on each of the new ones rather than trusting this note.
>
> **STILL STAY LIVE, and the list grew too:** #250, #252 and #254 were
> deliberately NOT closed (each owes a residual — 250-D's island watch, the
> Voice-card accent bar 252R-A, and #254's watch with a newly identified
> mechanism). **#241 was closed and then REOPENED the same day** as
> TRACK-UPSTREAM — do not sweep it. #257 and #297 stay live as before.
>
> **The baseline is unchanged at live 124 / archive 179 / union 303** — closed
> items migrate at cleanup passes, not instantly, which is exactly what this
> sweep is for. Re-measure at execution time regardless; the count moved four
> times in one day.


**Item:** none (housekeeping across the whole tracker). **Goal:** move every
item that is genuinely, wholly closed from `OPEN_ITEMS.md` to
`OPEN_ITEMS-ARCHIVE.md`, VERBATIM, with a verification procedure that does not
depend on the pinned `oi-split-verify.py`.

This dispatch does not move anything. Executing it is a separate lane.

---

## 1. Verified state

### 1a. Step 0 — the counting baseline, RE-MEASURED, and the outline's number is wrong

The outline in `handoffs/HANDOFF-2026-08-08-284-LANE-CLOSED-MERGED.md` §🗃️
records **"Live 118 · archive 180 · total 298."** That is stale by more than
one day's drift — it undercounts because it was computed before canonicalization
was applied consistently, dropping the six letter-suffixed live items. Re-run
yourself before trusting this document or that one:

```bash
grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS.md | sort -u | wc -l
grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS-ARCHIVE.md | sort -u | wc -l
cat OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md | grep -oE '^## [0-9]+[A-Z]?\.' | sort -u | wc -l
comm -12 <(grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS.md | sort -u) \
         <(grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS-ARCHIVE.md | sort -u)   # must be empty
```

**VERIFIED, measured 2026-08-09 at HEAD (`35c6234`):**

| | count |
|---|---|
| Live (`OPEN_ITEMS.md`) | **124** |
| Archive (`OPEN_ITEMS-ARCHIVE.md`) | **179** |
| Union | **303** |
| Overlap (must be empty) | empty — confirmed disjoint |

**124 + 179 = 303. This is THE baseline the sweep's own set-arithmetic check
must reproduce.** The six letter-suffixed live items the 118-count silently
dropped: `#198A`, `#198B`, `#199A`, `#205E`, `#210A`, `#211A` — all present and
correctly matched by the canonical `## N.` / `## NL.` regex. Do not carry
"118 · 180 · 298" into the sweep in any form; it fails its own arithmetic
before the first block moves.

**⚠️ Operational note, VERIFIED, not this dispatch's doing:** as of this
writing the working tree already carries an **uncommitted** diff to
`OPEN_ITEMS.md` (`git status` shows `M OPEN_ITEMS.md`; `git diff OPEN_ITEMS.md`
shows two Owen rulings dated 2026-08-09 appended inside the bodies of **#282**
and **#280** — no headers added or removed, so it does not change the 124/179/303
figures above). This dispatch did not create that diff and does not touch it.
The sweeper should decide — before starting — whether to commit that diff
first (recommended, so the sweep's own before/after commits are clean) or
carry it along; either way, **re-run the Step 0 commands again at the moment
the sweep actually starts**, don't reuse the numbers in this document blindly
if time has passed.

### 1b. Step 1's rule, restated with teeth, and independently re-checked

**A ✅ anywhere in a header does not mean closed.** An item moves only when
the ✅ covers the WHOLE item and no residue is owed anywhere — **including
`dispatch/DEVICE-PASS-RUNNING-LIST.md`.** I checked the outline's six
verified-must-stay-live examples myself rather than trusting the outline;
all six reconfirmed, headers quoted verbatim at HEAD:

| # | header line (verbatim, truncated) | live? | residue |
|---|---|---|---|
| **21** | "Tier 1 ✅; Tier 2 relay route ✅; Tier 2 app-side fetch MERGED … dual-host device pass owed" | yes, `OPEN_ITEMS.md:266` | dual-host device pass — running-list Group 1, Group 5 rows still open |
| **24** | "422 → Mac-side … diagnostics-panel check (#24e) still open; relay-JWT persistence CLOSED (#24f)" | yes, `:494` | #24e explicitly still open in the item's own header |
| **33** | "device-side EventKit shipped; Mac-host layer LIVE … FindMy parked, Photon rejected" | yes, `:670` | Mac-host layer partial by the header's own words |
| **186** | "✅ VERIFIED ON MAIN 2026-08-04; only the device checks remain, queued in the running list" | yes, `:4479` | running-list Group 3 row, explicit |
| **229** | "✅ BUILT 2026-08-04 … 229-A/B GREEN, 229-C met on archived numbers" | yes, `:9610` | superseded/subsumed by #284's later token-budget work; not itself in the candidate set |
| **228** | "✅ L0-A + L0-C ON-DEVICE HALVES MET … " | yes, `:9723` | "halves" — by construction other halves are open |

All six confirmed still LIVE with header-visible residue. The outline's claim
holds; do not move any of these six in this pass.

---

## 2. The candidate set — each with residue actually checked

Eight candidates named by the dispatch brief: **#78, #285, #286, #295, #291,
#294, #273, #284.** Verdicts below are each backed by (a) reading the item's
full entry at HEAD, (b) grepping `dispatch/DEVICE-PASS-RUNNING-LIST.md` for
that item number, and (c) for anything claiming a merge, confirming the merge
commit exists on `main` via `git log`.

| # | Verdict | Evidence |
|---|---|---|
| **78** | **MOVE** | `OPEN_ITEMS.md:1526`. Header: "✅ CLOSED 2026-08-07 evening — 78-F2 MET ON THE LOCAL BRAIN (OTA 2171)… ready for the archive sweep." Every sub-bar 78-A through 78-G plus 78-F2 individually confirmed MET in the entry's own closing note (`:1839-1842`). Device-list Group 1 row for #78 is struck with the same OTA-2171 close-out. **Cleanest candidate — no residue found anywhere.** |
| **285** | **MOVE, header needs a correction first** | `OPEN_ITEMS.md:5914`. Bars 285-A/B/C/D all MET with named tests; residual race window explicitly routed to **#288**, not left here (`:5931-5939`, `:5754-5774` in #288's own entry) — confirmed #288 stays live and is NOT in this candidate set, so nothing is being buried. **BUT the header text at line 5914 reads "…merge is Owen's call"** — stale. `git log --oneline main \| grep 281` → `82625c8 Merge pull request #281 …`, dated 2026-08-08 01:39. **Correct the header to say MERGED (PR #281, `82625c8`) before or as part of the move** — see §3. |
| **286** | **MOVE** | `OPEN_ITEMS.md:5788`. Header already says "✅ FIX LANDED 2026-08-08 — bars 286-A..F MET." `git log` confirms `eca58b3 Merge pull request #283`. Device-list §Z3 is explicitly "cheap, fold into any sitting" — opportunistic only, no blocking bar. No stale merge-status language in the entry. Clean. |
| **295** | **MOVE** | `OPEN_ITEMS.md:5287`. Header: "✅ FIX LANDED 2026-08-08 — bars 295-A/B/C MET, gate PASS." `git log` confirms `29fa34a Merge pull request #284`. Device-list §Z4 says explicitly "OPPORTUNISTIC ONLY — do NOT schedule" and gives the reason bars are unit-pinned instead of device-pinned (the path cannot be triggered on demand). No residue owed. Clean. |
| **291** | **MOVE, header needs a correction first** | `OPEN_ITEMS.md:5549`. Bars 291-A/B/C/D all MET, **291-D is the device bar and is explicitly MET on device** (`:5610-5617`, OTA 2191, Owen's own two-minute hold). **But the close-out note at line 5594 still reads "AWAITING PR + Owen's read."** `git log` confirms `b54ec1e Merge PR #280: Stop settles the user's row; no ghost bubble (#291,#294,#293)` — already merged. Not referenced anywhere in the device-pass list beyond the already-struck 291-D. **Correct the stale "AWAITING PR" line before moving** — see §3. |
| **294** | **MOVE** | `OPEN_ITEMS.md:5410`. Bars 294-A/B/C all MET (`:5437-5453`), same lane/PR as #291 (`b54ec1e`, confirmed merged). No stale merge-status text in this entry (it never claimed "awaiting"). Not present anywhere in the device-pass list. Clean. |
| **273** | **JUDGMENT CALL — see §2a, recommend STAY** | `OPEN_ITEMS.md:6701`. Header says "✅ SWEPT 2026-08-07," all four of its own bars MET. But this item's BODY **is** the standing rule ("write this into any future review lane's dispatch…"), and I could not find that rule text duplicated anywhere else that a future session actually reads by default — see §2a. |
| **284** | **JUDGMENT CALL — Owen's, per the brief** | `OPEN_ITEMS.md:6188`. See §2b. |

### 2a. A third judgment call the brief did not name: #273

The brief flagged #284 and #257/#297 as judgment calls. Checking #273's
residue (as instructed, not assumed) surfaced a third one of the same shape.

#273 is not a defect-fix record like #78 — its own text says why it exists:
*"Rule written down here so it is not rediscovered a third time."* It is a
**standing convention**, and `OPEN_ITEMS.md`'s own framing (the file's header,
`:9-11`) says this file is *"the LIVE BOARD: open / watch / decision items
**plus the standing conventions**."* I grepped for the rule's actual text
(the blockquote starting "When a lane produces exploit-shaped detail…") across
the repo:

```bash
grep -rln "does not.*land in the repo first\|exploit-shaped" \
  --include="*.md" . | grep -v '\.claude/worktrees'
```

Result: it exists **only** inside `OPEN_ITEMS.md` #273 itself. The two other
files the grep also matches (`dispatch/DEVICE-PASS-RUNNING-LIST.md`,
`planning/LAUNCH_PASS-2026-07-20.md`) carry only the derived **clinical
sentence** ("mechanics in the out-of-repo security addendum, &lt;date&gt;"),
never the rule itself. `CLAUDE.md` does not carry it either (checked by
reading the whole file). So today, the ONE place a future session encounters
this convention while it is still "live" is this entry.

This is the same shape as **#3/#6/#7/#83** — the four items the file's own
counting rules (`OPEN_ITEMS.md:~46-50`) name as **"pure records"** that stay
in the live file forever despite being terminal, precisely because they are
conventions/decisions rather than tracked work. #273 fits that description
better than it fits "closed defect ready to archive." **Recommend: STAY, by
the same precedent** — but this is explicitly a call for Owen, not something
this dispatch resolves; flag it exactly like the other two.

### 2b. #284 — the split-state judgment call, evidence for Owen

`OPEN_ITEMS.md:6188`. Header still says "NO LANE, NO BARS … Owen routes" —
**stale**, since the lane ran to a filed verdict same day. What actually
happened, entirely from the entry's own later blocks:
- Stages 1–2 **shipped**: `CapabilityRegistry`, the #257 armed-surface fix,
  the `fullBelt=` budget contrast, DEBUG probe artifacts (`:6306-6314`).
- Selective arming **did not ship** — its own pre-registered danger bar
  (≤2%) measured **4.76%**, and the pre-registered response ("stages 1-2
  ship, arming does not") was taken without renegotiation (`:6310`,
  `:6313`).
- The lane's own meta-row finding was **withdrawn** same day on device
  evidence and re-routed into **#297**, which itself ran 2026-08-09 and
  **missed its bar** (`:6316`, cross-referenced at `#297` `:5201-5250`).

So: is #284 "closed" (a bounded lane that ended honestly, verdict filed,
nothing owed) or "live" (the broker idea is unfinished and #150/#163 land
into it later, per its own "Where it would live" section, `:6217-6224`)?
**This dispatch takes no position — the outline is explicit that this is
Owen's call, and the entry is the only home of the vector-probe verdict and
the danger-bar numbers, so moving it wrong would bury evidence exactly like
moving #257 or #297 would.** Present both readings to Owen; do not default
to either.

---

## 3. ⚠️ Tracker corrections (upstream, in the same commit as the sweep — THE CLOSE-OUT RULE)

Two stale merge-status claims, found while checking residue, that falsify
current state and must be corrected **in the items' own homes** before or as
part of the move (not downstream, per THE CLOSE-OUT RULE):

1. **`OPEN_ITEMS.md:5914` (#285 header)** — reads *"Branch
   `claude/t27-285-profile-atomicity`; merge is Owen's call."* PR #281 merged
   2026-08-08 01:39 (`82625c8`). Replace with a MERGED note naming the PR and
   commit before archiving.
2. **`OPEN_ITEMS.md:5594` (#291 close-out note)** — reads *"AWAITING PR +
   Owen's read."* PR #280 merged (`b54ec1e`, bundling #291/#294/#293a/#293c).
   Replace with a MERGED note before archiving.

Verify both with:
```bash
git log --oneline main | grep -E "Merge pull request #281|Merge PR #280"
```

No other stale claims found in the six candidates confirmed MOVE (#78, #286,
#295, #294) — their close-out text already states the correct merged/landed
status.

---

## 4. Proposed bars

This is docs-only tracker housekeeping, not a code lane — "bars" here means
the verification the move itself must satisfy, not a device/unit measurement.
Propose these for whoever files the actual sweep (bars live in the OPEN_ITEMS
entry per THE CLOSE-OUT RULE; this dispatch does not file them):

- **ARC-A (byte-identity):** every block that moves is byte-identical between
  its pre-sweep text in `OPEN_ITEMS.md` and its post-sweep text in
  `OPEN_ITEMS-ARCHIVE.md`. Zero reformatting, zero summarizing.
- **ARC-B (set arithmetic):** `live ∪ archive` after the sweep equals
  `live ∪ archive` before the sweep (303, or whatever Step 0 measures at
  sweep time); the two files stay disjoint; `len(live) + len(archive)` is
  conserved.
- **ARC-C (no renumbering):** no item id is invented, dropped, or reused.
  (Subsumed by ARC-B's set equality, but call it out — it is #261's core
  promise and the thing most worth a human double-check.)
- **ARC-D (corrections travel with the move, not after it):** the two stale
  merge-status corrections in §3 land in the SAME commit as the sweep, in the
  items' own text, not as a follow-up.
- **ARC-E (judgment calls resolved, not defaulted):** #284 and #273 (and the
  already-settled #257/#297 "stays live") are routed by an actual Owen
  decision recorded in the sweep commit message or the items themselves, not
  silently moved or silently left because the sweeper couldn't decide.

---

## 5. Task breakdown — runnable commands

```bash
# 0. Baseline, from a clean tree on main, BEFORE any edit.
cd /Users/owenjones/Documents/Claude/Talaria-27
git status --short                      # decide what to do with the pre-existing
                                         # uncommitted OPEN_ITEMS.md diff (§1a) first
PRE=$(git rev-parse HEAD)
grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS.md | sort -u | wc -l
grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS-ARCHIVE.md | sort -u | wc -l

# 1. Owen's calls, gated before any file edit:
#    - #284: closed-lane-with-verdict vs still-live-broker-idea (§2b)
#    - #273: standing-rule-stays-live vs archive-with-the-rest (§2a)
#    (Both #257 and #297 already resolved: STAY LIVE, not in the candidate set.)

# 2. Correct the two stale merge-status lines in place (§3), same commit as the move.

# 3. Move MOVE-verdict blocks verbatim: #78, #285, #286, #295, #291, #294
#    (+ #273 and/or #284 per Owen's calls). Cut the block from OPEN_ITEMS.md,
#    paste unmodified (except the two corrections above) into
#    OPEN_ITEMS-ARCHIVE.md. Preserve each file's existing ordering convention
#    (OPEN_ITEMS-ARCHIVE.md is not required to stay numerically sorted today —
#    check its current order before picking an insertion point, don't assume).

# 4. Verify. Commit first, THEN check the committed result — the byte-identity
#    check below reads from git, not the working tree, on purpose (same
#    reasoning as the pinned script: a git-committed comparison can't be
#    fooled by an editor autosave or a half-finished paste).
git add OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md
git commit -m "docs(#261-followup): archive sweep — move N closed items verbatim (#list); correct #285/#291 stale merge-status text"
POST=$(git rev-parse HEAD)

python3 - "$PRE" "$POST" <<'PY'
import re, subprocess, sys
PRE, POST = sys.argv[1], sys.argv[2]
HDR = re.compile(r"^## ([0-9]+[A-Z]?)\.")

def show(commit, path):
    r = subprocess.run(["git", "show", f"{commit}:{path}"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"cannot read {path} at {commit}: {r.stderr.strip()}")
    return r.stdout

def parse(text):
    lines = text.splitlines(keepends=True)
    starts = [i for i, ln in enumerate(lines) if HDR.match(ln)]
    out = {}
    for j, s in enumerate(starts):
        e = starts[j + 1] if j + 1 < len(starts) else len(lines)
        out[HDR.match(lines[s]).group(1)] = "".join(lines[s:e])
    return out

pre_live = parse(show(PRE, "OPEN_ITEMS.md"))
pre_arch = parse(show(PRE, "OPEN_ITEMS-ARCHIVE.md"))
post_live = parse(show(POST, "OPEN_ITEMS.md"))
post_arch = parse(show(POST, "OPEN_ITEMS-ARCHIVE.md"))

fail = []
pre_ids, post_ids = set(pre_live) | set(pre_arch), set(post_live) | set(post_arch)
if pre_ids != post_ids:
    fail.append(f"UNION CHANGED: lost={sorted(pre_ids-post_ids)} invented={sorted(post_ids-pre_ids)}")
overlap = set(post_live) & set(post_arch)
if overlap:
    fail.append(f"NOT DISJOINT post-sweep: {sorted(overlap)}")
if len(post_live) + len(post_arch) != len(pre_ids):
    fail.append(f"COUNT MISMATCH: {len(post_live)} live + {len(post_arch)} archive != {len(pre_ids)}")

# Byte-identity is scoped to items that actually MOVED (live pre-sweep ->
# archive post-sweep) -- NOT to every item, unlike the pinned script. Ordinary
# same-file corrections to items that stayed put (THE CLOSE-OUT RULE) are
# expected and must not fail this check; that scoping is exactly what let the
# pinned script decay into a false alarm the moment the tracker kept moving.
moved = sorted(i for i in pre_live if i in post_arch)
for i in moved:
    if pre_live[i] != post_arch[i]:
        # allow the two named corrections (§3) as the one intentional exception,
        # same shape as the pinned script's NOTE_EXEMPT for #261 itself
        if i in {"285", "291"} and post_arch[i].startswith(pre_live[i].split("Branch")[0].split("AWAITING")[0][:40]):
            continue
        fail.append(f"#{i}: NOT byte-identical (live pre-sweep -> archive post-sweep)")

print(f"pre:  {len(pre_live)} live + {len(pre_arch)} archive = {len(pre_ids)}")
print(f"post: {len(post_live)} live + {len(post_arch)} archive = {len(post_ids)}")
print(f"moved this sweep: {moved}")
if fail:
    print("FAIL"); [print(" -", f) for f in fail]; sys.exit(1)
print("PASS")
PY
```

The exemption clause in the byte-identity loop is intentionally narrow (named
ids only, prefix-match up to the correction point) — do not widen it into a
general "allow any diff" rule, or it silently re-creates the pinned script's
failure mode.

---

## 6. Traps

- **THE HEADLINE TRAP: `scripts/oi-split-verify.py` will NOT verify this
  sweep, and green output from it proves nothing about today's tracker.** Its
  own docstring: *"a ONE-SHOT PROOF OF A HISTORICAL COMMIT RANGE… does NOT
  read the working tree."* Both ends are pinned to `8077ecb`/`af59ea7`
  (2026-08-06). Running it today, on any arguments, either fails on it (if
  you pass different commits, its `NOTE_EXEMPT = "261"` and hardcoded prose
  will misfire on THIS sweep's corrections) or silently proves only that the
  old split is still intact, which nobody is asking. **Do not run it as part
  of this pass. Use §5's verifier instead.**
- **A stale header is not proof of state.** #285 and #291 both show this:
  fully MET bars sitting under header text that still claims "not yet
  merged." Read the whole entry, then check `git log`, before trusting either
  extreme.
- **Late-night sweeps are how counts get broken** — #78's own closing note
  says so explicitly ("ready for the archive sweep… deliberately not moved
  tonight"). Do this in one sitting, in daylight, per the outline's own
  opening line.
- **The pre-existing uncommitted `OPEN_ITEMS.md` diff (§1a)** is not this
  dispatch's and not necessarily the sweeper's — but it WILL show up in
  `git status` and WILL be included in whatever the sweeper's next commit
  touches unless explicitly handled first. Decide, don't let it ride along
  by accident.

---

## 7. What is Owen's to decide

1. **#284** — closed-lane-with-verdict vs still-live-broker-idea (§2b). Both
   readings are defensible; this dispatch does not default to either.
2. **#273** — standing-rule-stays-live (like #3/#6/#7/#83) vs archive-with-
   the-rest (§2a). Not named in the original brief; surfaced by checking
   residue as instructed.
3. **Confirmed, not a new ask, just restated so it isn't relitigated:** #257
   and #297 **stay live regardless** — moving either would bury a bar that
   MISSED (#297's device A/B, 7/20 vs ≥18/20) under a ✅-shaped header.
4. **The `oi-split-verify.py` question** — see §8: recommend filing as its
   own item, not building now. Confirm that routing.

---

## 8. `oi-split-verify.py` — recommendation on a live mode

**Not a flag-sized change. Recommend filing as its own tracker item, per
#268 ("a phase name is not a filing") — do not build it inside this docs
pass.**

Why it is more than parameterizing the two commit args (which the script
already accepts positionally — `BASE`/`SPLIT` are `sys.argv[1]`/`[2]` today):

- **The byte-identity check (261-A) currently applies to EVERY item, not just
  moved ones**, comparing each item's pre-commit text against wherever it
  landed. That is exactly the design the script's own docstring says decayed
  into 27 false failures the moment the tracker kept moving after the pinned
  split — ordinary same-file corrections to items that never moved got
  flagged as violations. A live mode needs the NARROWER rule §5 uses above
  (byte-check only items that changed FILE), which is a different algorithm,
  not a different pair of commit arguments.
- **`NOTE_EXEMPT = "261"` is hardcoded to one item.** A live mode needs this
  generalized to whatever correction the CURRENT sweep makes (this pass
  needs #285 and #291 exempted, not #261) — either a CLI-supplied exemption
  list or the narrower moved-only byte-check above (which makes the
  exemption problem mostly disappear, another reason to prefer that design).
- **User-facing text is written in prose about "the 2026-08-06 split"**
  specifically (`print()` lines, the docstring, bar names 261-A/B/C) — a live
  mode's output needs to describe whichever sweep it's checking, not a fixed
  historical one.

None of that is dangerous to build, but it is a small, real feature with its
own correctness risk (get the "which items get byte-checked" scoping wrong
and you reinvent the exact false-alarm failure mode that got the original
script pinned). File it, name the scoping design in the filing, and let a
future lane build and prove it — the ad hoc verifier in §5 is sufficient for
THIS sweep in the meantime.

---

## 9. Close-out

One commit. Message names every item moved, the two corrections, and the
before/after counts (e.g. "move #78/#285/#286/#295/#291/#294[/#273][/#284]
verbatim; correct #285 and #291 stale merge-status text; 124→N live,
179→M archive, 303 conserved"). Run §5's verifier against that commit and
its parent before calling the pass done. Update
`dispatch/DEVICE-PASS-RUNNING-LIST.md`'s Owen's-queue pointer if any struck
item was the running list's own citation target (it currently cites #78 and
#273 by number in a couple of rows — those citations stay valid since numbers
never change, but double check no row assumed the item would still be
readable "here" in `OPEN_ITEMS.md` specifically rather than by number).
