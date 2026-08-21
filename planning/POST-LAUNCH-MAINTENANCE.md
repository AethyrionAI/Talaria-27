# Post-launch ongoing maintenance — the running list

**Started 2026-08-20** at Owen's direction, the day PCC shipped and the privacy
policy had to start quoting Apple.

**What belongs here:** recurring obligations that only begin once Talaria is
live — things that must be *watched* or *re-checked on a cadence*, not built
once and finished. A one-off task belongs in `OPEN_ITEMS.md` with a number.
**This list is for work that never completes.**

**What each entry owes:** what is watched, why it matters, what a change
*means*, who decides, and the cadence. An entry that says only "check X
periodically" is not actionable and will be ignored on the day it fires.

**Nothing here is built yet.** These are obligations being written down while
the reason for them is fresh — the mechanism is chosen at launch, not now.
Anything touching a live Hermes install needs Owen's per-experiment go
(CLAUDE.md's standing rule); anything outward-facing needs his read of the
exact text.

---

## 1. Watch Apple's Private Cloud Compute pages for wording changes

**Cadence:** weekly is probably right; daily is cheap if the mechanism is a
diff. Decide at setup.

**What to watch**
- `https://www.apple.com/privacy/` — the PCC section. **This is the load-bearing
  one**: it is what the privacy policy cites.
- `https://www.apple.com/apple-intelligence/` — the PCC block. Secondary; same
  claims in marketing register.

**Why this exists.** `docs/privacy.html` **quotes Apple directly**, dated
*"as published at apple.com/privacy on 2026-08-20"*, on Owen's ruling that we
quote rather than paraphrase (#386). Quoting is the honest choice — attributing
the claim to Apple rather than laundering it into our own voice — but **it
makes us the holder of a snapshot.** Apple's page is not ours and can change
without notice.

**What a change MEANS, which is the part that is easy to get wrong.** A diff is
not automatically a problem:
- **Cosmetic rewording** — no action; the dated quote is still accurate as a
  quote.
- **A weakened or withdrawn guarantee** — this is the one that matters. Our
  policy would still be reporting a promise Apple no longer makes. **Act
  immediately**: the policy is a document users rely on.
- **A strengthened guarantee** — worth adopting, not urgent.
- **The page moved or 404s** — the citation link is broken in a legal document.
  Fix the link; do not silently drop the quote.

**Who decides.** Owen. The policy is outward-facing, so any edit needs his read
of the exact wording plus an explicit go. **A watcher may report; it may not
edit and it may not publish.**

**Mechanism, undecided.** A Hermes cron job (the gateway has `/api/cron/fire`)
or a Cowork scheduled task. Whichever is chosen, the useful output is a **diff
of the relevant section**, not "the page changed" — a page-level hash will fire
on every unrelated marketing tweak and get muted within a month, which is the
normal way watchers die.

**Also worth watching in the same job, once the App Store listing exists:** the
App Store privacy "nutrition label" answers depend on the same facts, and
`PrivacyInfo.xcprivacy` (three targets) may too. Not yet checked whether PCC
requires anything there — #386 records that as an open question rather than an
assumption.

---

*(Add entries below. Keep the shape: what, why, what a change means, who
decides, cadence.)*
