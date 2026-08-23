# #308 pre-publish scrub — `AethyrionAI/talaria-plugin`

**Date:** 2026-08-23
**Target:** `/Users/owenjones/.hermes/plugins/talaria` (live plugin checkout; scrub was strictly read-only)
**Scope:** working tree + full git history, all refs

## Repo identification

- Git repo: **yes.** Remote `origin` = `https://github.com/AethyrionAI/talaria-plugin.git` (fetch + push).
- HEAD: `fb2e3649b2b4ee8ba119b5e4f4dd17b9a40043de` on `main` (2026-08-22, "#396-B: turn detection becomes configuration…").
- Working tree: **clean** (no modified, no untracked). No stash. No tags.
- 44 commits total across all refs. Branches: local `main`, `claude/t27-263-transport-instrumentation` (checked out in another worktree); remotes `main`, `363-outbox-hygiene`, `3d-artifact-mirror`, `claude/t27-263-transport-instrumentation`, `t27-260-denial-prose`. **Every ref tip is reachable from `main`** (`git log --all --not main` is empty) — there is no orphan or side-branch-only history to reason about separately.
- 39 tracked files. History-deleted files: `pyproject.toml`, `tests/test_packaging.py` (removed at `bb912f2`), `tests/__init__.py` (removed at `6b53270`) — all three inspected, nothing sensitive (packaging metadata only).

## Summary table

| # | Category | BLOCKS-PUBLISH | NEEDS-OWEN-DECISION | FINE (notable) |
|---|----------|:---:|:---:|:---:|
| 1 | Secrets | 0 | 0 | 2 |
| 2 | Host specifics | 0 | 1 (OJAMD) | 2 |
| 3 | Tailnet | 0 | 1 (whoGoesThere) | 1 |
| 4 | Identity | **1 (personal email, 43/44 commits)** | 1 (first name in contents) | 1 |
| 5 | Naming (#255) | 0 | 0 | 2 (both COSMETIC) |
| 6 | Attack mechanics | 0 | 0 | 4 |
| 7 | Attribution | 0 | 1 (no LICENSE + connector-port attribution) | 1 |
| 8 | Compatibility signal | 0 | 1 (nothing exists; pick a home) | — |
| | **Total** | **1** | **5** | |

The single BLOCKS-PUBLISH finding is history-resident, so it forces a history rewrite or a fresh-history publish — and that remedy incidentally clears every history copy of the NEEDS-OWEN-DECISION items too.

---

## 1. Secrets — CLEAN

Swept tree and full `git log -p --all` for: 64-char hex (`API_SERVER_KEY` shape), `sk-` prefixed keys, `.env`/token/secret/credential files ever added (`--diff-filter=A`), bearer literals, `talaria_shim_token`.

- **No 64-hex string anywhere** — tree or any commit.
- **No `sk-` key anywhere.**
- **No `.env`, token, or credential file was ever committed.**
- FINE (notable): `tests/test_envelope.py:13-14` — the test API key is a runtime-constructed dummy (`"test-api-key-" + "64chars-" + "a" * 43`, asserted 64 chars), deliberately built this way at commit `457de49` so Hermes's plugin-guard scanner stops flagging it. Clearly labeled, no entropy, not a secret.
- FINE (notable): `talaria/voice.py:84-95` *reads* `OPENAI_API_KEY` from the environment or `<HERMES_HOME>/.env` at runtime — key-resolution code, no key material.
- `.gitignore` coverage: `*.db`/`*.db-shm`/`*.db-wal` (the runtime DB holding hashed pairing tokens), `__pycache__/`, `.pytest_cache/`, `.venv/`, `.DS_Store`, `.superpowers/`. It does **not** list `.env` — the plugin never keeps a repo-local `.env` (resolution reads `$HERMES_HOME/.env`, outside the repo), so nothing is exposed today, but adding `.env` is cheap belt-and-braces before going public.

## 2. Host specifics

- **No** `O:\Hermes`, `C:\Users\Owen`, or `/Users/owenjones` paths — tree or history.
- FINE: `HERMES_HOME` references throughout (`talaria/voice.py:61-63`, `talaria/store.py:3`, `README.md:75`, tests) — the generic Hermes convention, exactly what a public plugin should use.
- FINE: `talaria/database.py:15` resolves the home via `hermes_constants.get_hermes_home()` — no hardcoding.
- **NEEDS-OWEN-DECISION — `OJAMD` hostname (2 tree sites + their introducing commits):**
  - `talaria/artifact_mirror.py:19` — "two-device host, measured on OJAMD 2026-08-18"
  - `tests/test_artifact_mirror.py:128` — "(OJAMD: iPhone + iPad, …)"
  - Introduced by `c1ff23f` (#366). Not addressable information, but it names private production infrastructure in what would become public provenance comments. Trivially rewordable to "a two-device production host."

## 3. Tailnet — near-clean

- **Zero** occurrences of `100.110.102.59`, `100.79.222.100`, any other `100.64.0.0/10` address, any IP other than `127.0.0.1`, any `*.ts.net` hostname, or `tail5663a6` — tree or history. All URLs in the repo are loopback (`dashboard/plugin_api.py:80`, test fixtures) or `api.openai.com` (`talaria/voice.py:52`).
- FINE: the *word* "tailnet" appears in design rationale (`talaria/voice.py:31,426`, `tests/test_voice.py:154` — "#85: OpenAI cannot reach a tailnet MCP endpoint") with no address attached.
- **NEEDS-OWEN-DECISION — `whoGoesThere` device name (2 tree sites + history):**
  - `tests/test_dashboard_api.py:46` and `:60` — used as a test fixture device name.
  - Introduced by the desktop-face commit `2ee1ad7` (#270); no other history occurrence. It is Owen's real iPhone's name. A one-word fixture rename ("test-phone") clears the tree; the history copy rides the identity remedy below.

## 4. Identity

- **BLOCKS-PUBLISH — personal email saturates commit history.** `git log --all --format='%an <%ae>'`:
  - `Chrono_Rixun <j.owen.jones@live.com>` — **43 of 44 commits**, as both author and committer (GitHub's `noreply@github.com` is committer on the web-UI merge commits). Every branch, from the root commit `3519972` through HEAD `fb2e364`.
  - `ChronoRixun <174843372+ChronoRixun@users.noreply.github.com>` — 1 commit (`457de49`), the correct public shape.
  - The *name* matches the public identity (`Chrono_Rixun`); the *email* is the personal `live.com` address. This cannot be fixed in the tree — it requires rewriting history (`git filter-repo` mailmap) or a fresh-history publish. Note GitHub also exposes this email on every commit page and in `.patch` URLs the moment the repo is public.
- **NEEDS-OWEN-DECISION — first name "Owen" in file contents** (ties to a real identity mainly *in combination with* the email above):
  - Decision-provenance comments: `talaria/voice.py:18` ("Owen ruled 2026-08-22"), `:123` ("Owen's 2026-08-22 characterisation"), `:309` ("per Owen's 2026-08-22 ruling"); `talaria/envelope.py:153` ("Owen's call; not built"); `tests/test_voice.py:277` ("the fault Owen actually…").
  - Test fixtures: `tests/test_admin_send.py:112,115`, `tests/test_database_migration.py:20`, `tests/test_store_pairing.py:14,19` (all `"Owen's iPhone"`); `tests/test_voice.py:69-76` (`"Owen ships at night."`, `"Owen. iOS. Talaria."`).
  - First-name-only, and "the operator ruled X" comments are genuinely load-bearing provenance. Options: keep as-is (low risk once the email is gone), or s/Owen/the operator/ in a pre-publish pass.
- FINE: no email addresses appear in any file contents, tree or history.

## 5. Naming — #255 (`hermes-mobile` / `hermes_mobile`)

Exactly **2** occurrences in the tree (and only their own introductions in history), **both COSMETIC** — no code path registers, reads, or emits either identifier:

- `talaria/voice.py:22` — docstring explaining that the connector's `readiness_summary` prompt input (native-MCP readiness for `hermes_mobile`, disabled by #346) was deliberately dropped in the port. **COSMETIC** (doc of an omission).
- `talaria/voice.py:87` — docstring noting the connector's `~/.hermes-mobile/secrets.json` store is deliberately *not* read by this plugin. **COSMETIC** (doc of a non-dependency).

No WIRE occurrences exist in this repo. Verdict: FINE — publishable as-is; both lines actively document that the legacy naming is *not* depended on.

## 6. Attack mechanics (#261 standing rule)

Nothing that meets the bar of attack mechanics, crafted exploit strings, or copy-pasteable probes against real endpoints. The four closest shapes, each examined:

- FINE: `dashboard/plugin_api.py:83-100` (`_probe_once`) — a deliberately **unauthenticated** `POST {}` to `http://127.0.0.1:{port}/api/platforms/talaria/events`, classifying 401→live / 503→absent (`classify_probe_status`, :68-75, the #269-A table). This is the product's own liveness probe: loopback-only, *expects* auth to reject, and the docstring establishes it is side-effect-free because auth precedes verb dispatch. It is a liveness check, not a bypass; no secret material, no external endpoint.
- FINE: `tests/test_envelope.py:168-174` — malformed-payload robustness test (`None`, string, list, int) under an "attacker-controlled" comment. Defensive, in-process, asserts clean rejection.
- FINE: `tests/test_transport.py:121-130` — regression test that a valid device-B token cannot answer device-A's query ("fabricated data injection"). Defensive spoof-*refusal* test, in-process.
- FINE: threat-model vocabulary in comments (`talaria/transport.py:193-196`, `talaria/envelope.py:151-153` — the note that the retired relay's verb "bypassed the user's own 'post voice transcripts' setting"). These describe defenses and a weakness in a component that is retired and private; no mechanics, no reproduction recipe. The CLAUDE.md-style bogus-token wire-probe curl recipe does **not** appear in this repo.

## 7. Attribution

- **No `LICENSE` file. No `THIRD_PARTY_LICENSES`.** `git ls-files` confirms; no license text has ever been committed. Publishing without one means "all rights reserved" by default — a must-resolve before publish, and the *choice* is Owen's. Reference point: the (private) Talaria-27 app repo is MIT, "Copyright (c) 2026 Hermes iOS Contributors."
- **NEEDS-OWEN-DECISION — connector-derived behavior in `talaria/voice.py`.** The module self-describes as "a PORT WITH DELIBERATE OMISSIONS, not a transcription" of the retired relay/connector's realtime voice bootstrap (`talaria/voice.py:13`), and carries behavior-parity markers: `DEFAULT_REALTIME_MODELS` "Matches the connector's list" (:50-51), and the response-shape handling "Both are handled because the connector handled" both (:453-469). The connector descends from the `dylan-buck/Hermes-iOS` upstream lineage (MIT). Whether a behavior-parity port of the bootstrap constitutes a "substantial portion" requiring the upstream MIT notice is a judgment call: the safe move is an MIT `LICENSE` plus a one-line upstream-heritage acknowledgment (README or a `NOTICE`), which costs nothing; the alternative is documenting it as a clean-room reimplementation. Everything else in the repo is greenfield plugin code against hermes-agent's public plugin API.
- FINE (needs a publish-day edit, not a decision): `README.md` links the private `AethyrionAI/Talaria-27` repo (:3-5) and closes with "Repository publication remains intentionally deferred while the Talaria app is private" (:last) — both need a truth pass in the publishing commit. `plugin.yaml` `author: AethyrionAI` is already the public identity.

## 8. Compatibility signal (the open #308 question)

**Nothing exists today.** Verified:

- `plugin.yaml` declares `name/version/description/author/kind/provides_tools` — **no `manifest_version`, no Hermes version floor, no tested-against tag.**
- `talaria/__init__.py::register(ctx)` performs no compatibility check, and is deliberately fail-soft (every sub-registration is wrapped in try/except "register must never break gateway load") — so today an incompatible Hermes degrades into partial registration with printed warnings rather than a named refusal.
- The only pin practice is operator-side: `README.md:26-30` installs by `--ref <full-40-character-commit-sha>` — it pins *the plugin*, asserts nothing about *the host*.
- CI (`.github/workflows/ci.yml:31-34`) clones `NousResearch/hermes-agent` at **floating HEAD** (`--depth 1`) — so "tested against" is whatever HEAD was on the last green run, recorded nowhere.

**The compat surface a floor would protect** (the imports that break first): `talaria/database.py:15` (`from hermes_constants import get_hermes_home, secure_parent_dir`), `talaria/platform_adapter.py:17-18` (`from gateway.config import Platform`, `from gateway.platforms.base import BasePlatformAdapter, SendResult`), the `ctx.register_platform`/hook signatures, and the `/api/platforms/{p}/events` route contract.

**Where a floor would naturally live** (in increasing strength):
1. `manifest_version: 1` in `plugin.yaml` — supported by the installer today (`hermes_cli/plugins_cmd.py:143-146` defines `_SUPPORTED_MANIFEST_VERSION = 1`; `:808-824` enforces it at install with a "run the update command" refusal). Note its semantics: it guards the manifest *schema* against a too-old installer — it cannot express "needs Hermes agent ≥ X" at runtime.
2. A load-time check in `register()` — read the running Hermes version, log a loud named warning (raising would violate the module's own fail-soft contract) when below a floor constant.
3. A README "Tested against Hermes vX (`<commit>`)" line, refreshed when CI's clone target changes.
4. Pin the CI clone to a tag/SHA instead of HEAD, which is what makes claim 3 reproducible rather than anecdotal.

## What a publish would require

**(a) Fixes in the tree (one pre-publish commit):**
- Add a `LICENSE` (Owen picks; MIT matches the app repo) and, per the decision above, an upstream-heritage note for `voice.py`'s connector-port lineage.
- README truth pass: private-repo link, "publication deferred" closing line, and (recommended) a tested-against line.
- Rename the `whoGoesThere` fixture in `tests/test_dashboard_api.py:46,60`; reword the two `OJAMD` comments (`talaria/artifact_mirror.py:19`, `tests/test_artifact_mirror.py:128`); optionally depersonalize the "Owen" comments/fixtures (§4).
- Add `.env` to `.gitignore` (belt-and-braces).
- Optionally declare `manifest_version: 1` and a compat signal per §8.

**(b) History rewrite or fresh-history publish — REQUIRED:**
- The personal email `j.owen.jones@live.com` is author+committer on 43/44 commits on every branch. Either `git filter-repo` with a mailmap to the `174843372+ChronoRixun@users.noreply.github.com` identity (rewrites every SHA — breaks the README's install-by-SHA pins and any deployed `--ref` pins, which must be re-issued), **or** publish fresh history: squash the scrubbed tree onto an orphan branch / new public repo and keep this repo as the private history. Fresh-history also clears every history copy of `whoGoesThere`, `OJAMD`, and the "Owen" strings in one move, and is the cheaper, lower-risk path given nothing in the history is load-bearing publicly.
- Independently: set `user.email` to the noreply address in this checkout so post-scrub commits stop re-introducing the finding.

**(c) Open decisions for Owen:**
1. License choice, and whether `voice.py`'s connector-port heritage gets an explicit upstream MIT notice or a clean-room statement (§7).
2. Publish mechanism: mailmap rewrite (keeps history public) vs fresh-history/orphan publish (recommended; keeps private history private) (§4/b).
3. Keep or depersonalize the "Owen ruled…" provenance comments and "Owen's iPhone" fixtures (§4).
4. Reword vs keep `OJAMD` (§2) and `whoGoesThere` (§3) — both trivial rewords.
5. Which compatibility-floor shape (if any) to adopt from §8 — this closes the open #308 question either way.
