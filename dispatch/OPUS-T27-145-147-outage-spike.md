# OPUS-T27-145-147 — SPIKE: the outage hard-lock and the inbox-alert crash

**Items:** OPEN_ITEMS #145, #147 · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** only if a fix is confidently identified — otherwise findings land as OPEN_ITEMS commits
**Output:** written findings on both items. A PR is a *possible* outcome, not the deliverable.
**Toolchain:** Xcode-beta4 · `export GH_PAGER=cat` first

## Read this first

**Both are unreproduced since 2026-07-20.** Owen deliberately excluded them from the build weekend
for that reason, then asked for the investigation lane. **This is a spike, like #58's** — and #58's
spike is the precedent worth copying: three device passes had been spent guessing; one source read
and one web search settled it in an hour.

**Do not implement a fix against a guess.** If the reading is inconclusive, the correct deliverable
is *"here are the two experiments that would settle it."* That is a better outcome than a fourth
confident fix — #58's history is made entirely of confident fixes.

## Standing caution — keep these two apart

**#146 and #147 were found in the SAME test and share the push surface.** #146's fix has since
shipped (PR #144, derived-Bool). A push-path change can wander from one into the other without
meaning to. Investigate #147 without touching #146's now-merged work.

---

# PART A — #147: inbox-alert notification tap crashes the app

## The critical fact that has changed since filing

The prime suspect is **GitHub PR #126** (merge `edeba74`) — the briefing/inbox-alert app half,
merged hours before taps started crashing.

**OPEN_ITEMS #126 was DROPPED on 2026-07-24 — but the code was NOT removed.** The drop note is
explicit: the app half stays merged and inert, no revert commit was owed, and *"#147 stays open on
its own merits — dropping #126 does not close #147."*

**So the suspect code is still in the app.** Do not read "briefing was dropped" as "the crash is
gone." It is not.

**Beware the number collision:** OPEN_ITEMS #126 (daily briefing, dropped) and GitHub PR #126 (the
app half, merged) are different sequences that happen to share a digit. The tracker warns about
this generally; here it is live.

## Investigate

- `git show edeba74 --stat`, then read the notification-tap handling it introduced.
- **Documented scope cut, and the likely culprit:** inbox alert pushes carry **NO identifying
  userInfo**, and tap deliberately routes to chat. A handler that unwraps something the payload was
  never designed to carry is the shape of this crash. Look for force-unwraps, non-optional casts,
  or array indexing on `userInfo`.
- `BriefingDetailScreen`, the widget, and `InboxStore.markRead` remain wired. Any of them reachable
  from a tap is in scope.
- **Live repro material may still exist:** Owen reported multiple identical notifications sitting
  on the lock screen. If any survive, tapping one with the device attached to Console would be
  decisive — ask before assuming they are gone.

## If a crash path is identified

A fix is in scope **only if the path is unambiguous** (a force-unwrap on a field the payload never
carries is unambiguous). Anything requiring a judgement call about routing behaviour: report,
do not build.

---

# PART B — #145: hard-lock during a gateway outage, no recovery without a phone restart

## Why this is NOT #136, and why that matters

**#136's verified pass was the INVERSE outage shape:** relay + shim black-holed with the **gateway
alive** — cold launch was instant and chat worked. This event is the **gateway down** with the rest
presumably alive. #136 passing does not cover this, and citing it as coverage would be wrong.

A **phone restart** was required. That is a strong signal: an app-level deadlock usually clears on
force-quit. Needing a restart points at something held below the app — a wedged system resource, a
stuck XPC/network connection, or a lock held across a process boundary.

## Investigate — from logs and source, not from a repro attempt

**Do not stage a `hermes update` outage to reproduce this.** It risks the working backend for an
unreproduced bug, and Owen's device time is committed to the device pass.

- What does the app do on entry when the **gateway `:8642`** is unreachable but the relay answers?
  Find the launch-path call that has no timeout, or one whose timeout exceeds the launch window.
- **#151's lane established three network shapes** — fast refuse, firewall black-hole (~60s),
  accepted-but-silent warmup. A bouncing gateway during `hermes update` is plausibly the *third*:
  the TCP connect succeeds and the response never comes. **A connection that is accepted and then
  silent is the one that hangs forever without a dedicated timeout.** That is the first hypothesis
  to test against source.
- Is any launch-path network call made **synchronously on the main actor**, or awaited before the
  first frame? That would explain a lock that survives backgrounding.
- Relay/shim state during the window was **unrecorded**. Say so plainly rather than assuming they
  were healthy.

## Deliverable

For each item: what was found, what remains unknown, and **either** a recommended fix with its
size, **or** the specific experiment that would settle it. Append to the items in a file-scoped
OPEN_ITEMS commit.

**If #145 comes down to "a launch-path call needs a timeout," say so and size it** — that is a real
answer and a small lane, and it would close a bug that currently requires a phone restart.

## Out of scope

Staging an outage on OJAMD. Touching #146's merged work. #136's verified behaviour. Any change to
the relay or gateway.
