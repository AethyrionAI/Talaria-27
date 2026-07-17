# FABLE T27-115 — Connector: resolve_mcp_command_path breaks on macOS venvs

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-115-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #115 · **Size:** micro-PR (Python only, no Xcode)

## The bug (verified in source at HEAD)

`connector/src/hermes_mobile_connector/mcp_registration.py:47`
`resolve_mcp_command_path()` does
`Path(sys.executable).resolve().with_name("hermes-mobile-mcp")` — `.resolve()`
FIRST follows the macOS venv python symlink out to the framework/uv binary,
escaping the venv, so the sibling lookup misses `.venv/bin/hermes-mobile-mcp`
and `setup` / `configure-mcp` report "Could not find hermes-mobile-mcp".
Windows venvs COPY the exe, which is why OJAMD never hit this — the bug is
macOS-only (and the Mac Mini is now a production host, so it matters).

Workaround in use on the Mini since 2026-07-14:
`PATH="$PWD/.venv/bin:$PATH" hermes-mobile configure-mcp` (the `shutil.which`
candidate wins). This lane deletes the need for it.

## The fix

In `resolve_mcp_command_path()`: try the UNRESOLVED sibling
(`Path(sys.executable).with_name("hermes-mobile-mcp")`) BEFORE the resolved
one. Keep the existing candidate order otherwise (which/PATH fallback stays).
Windows behavior must be unchanged.

## Tests (pytest, `connector/tests/`)

- macOS-shape: symlinked `sys.executable` whose unresolved sibling exists →
  returns the venv path (monkeypatch `sys.executable` + tmp dirs; do not
  require a real venv).
- Windows-shape: copied exe, no symlink → unchanged result.
- Neither sibling exists → falls through to `shutil.which` as today.

## Constraints & acceptance

- Connector suite green: baseline **115 passed** on macOS (`.venv/bin/pytest`),
  114+1 skip on Linux. No relay changes, no app changes, no Xcode loop.
- PR body notes the Mini deploy step: after merge, plain
  `hermes-mobile configure-mcp` (no PATH override) must succeed there —
  that's the device check, Owen/Desktop runs it.
