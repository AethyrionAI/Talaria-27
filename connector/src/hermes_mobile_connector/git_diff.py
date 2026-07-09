"""Git diff capture for detecting file changes made by Hermes during a job.

Captures a snapshot of the working tree before the job runs, then diffs
against it after the job completes to isolate exactly what Hermes changed.

No Hermes framework modifications required — this uses standard git commands
on the same working directory that Hermes operates in.
"""

from __future__ import annotations

import asyncio
import difflib
import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

# Maximum total patch size to include in the job result (bytes).
# Prevents enormous diffs from bloating WebSocket messages.
MAX_PATCH_BYTES = 64_000


@dataclass(frozen=True)
class WorktreeSnapshot:
    """A frozen snapshot of which files have changes, taken before a job runs."""

    # file path → porcelain status code (e.g. " M", "??", "A ")
    entries: dict[str, str]
    # file path → UTF-8 text captured at snapshot time (None if unreadable/missing)
    before_text: dict[str, str | None]


async def capture_snapshot(workdir: str) -> WorktreeSnapshot | None:
    """Record which files are dirty/untracked before Hermes runs.

    Returns *None* if the directory is not a git repo or git is unavailable.
    """
    try:
        result = await asyncio.to_thread(
            subprocess.run,
            ["git", "status", "--porcelain"],
            cwd=workdir,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
        if result.returncode != 0:
            return None

        entries: dict[str, str] = {}
        before_text: dict[str, str | None] = {}
        for line in result.stdout.splitlines():
            if len(line) < 4:
                continue
            status_code = line[:2]
            file_path = line[3:]
            # Handle renamed files ("R  old -> new")
            if " -> " in file_path:
                file_path = file_path.split(" -> ", 1)[1]
            entries[file_path] = status_code
            before_text[file_path] = _read_text(Path(workdir) / file_path)
        return WorktreeSnapshot(entries=entries, before_text=before_text)

    except Exception:  # noqa: BLE001
        logger.debug("Failed to capture git snapshot in %s", workdir, exc_info=True)
        return None


async def capture_diff(workdir: str, pre: WorktreeSnapshot | None) -> dict | None:
    """Compare current working tree to the pre-job snapshot.

    Returns a dict suitable for JSON serialization::

        {
            "files": [
                {"path": "...", "status": "modified", "additions": 5,
                 "deletions": 2, "patch": "..."},
                ...
            ],
            "summary": "2 files changed, 15 insertions(+), 3 deletions(-)"
        }

    Returns *None* if there are no new changes or git is unavailable.
    """
    if pre is None:
        return None

    try:
        # Current state
        result = await asyncio.to_thread(
            subprocess.run,
            ["git", "status", "--porcelain"],
            cwd=workdir,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
        if result.returncode != 0:
            return None

        post_entries: dict[str, str] = {}
        for line in result.stdout.splitlines():
            if len(line) < 4:
                continue
            status_code = line[:2]
            file_path = line[3:]
            if " -> " in file_path:
                file_path = file_path.split(" -> ", 1)[1]
            post_entries[file_path] = status_code

        # Files that Hermes touched: status changed, path disappeared/appeared,
        # or content changed while the porcelain status stayed the same.
        changed_files = [
            path
            for path in sorted(set(pre.entries) | set(post_entries))
            if _path_changed(workdir, path, pre, post_entries)
        ]

        if not changed_files:
            return None

        # Get unified diff for each changed file
        files = []
        total_patch_bytes = 0

        for path in sorted(changed_files):
            status_code = post_entries[path]
            file_status = _classify_status(status_code)

            if path in pre.before_text:
                patch = _diff_from_snapshot(path, pre.before_text[path], _read_text(Path(workdir) / path))
            elif status_code.strip() == "??":
                # Untracked (new) file — use diff against /dev/null
                diff_result = await asyncio.to_thread(
                    subprocess.run,
                    ["git", "diff", "--no-index", "--", "/dev/null", path],
                    cwd=workdir,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=5,
                )
                patch = diff_result.stdout
            else:
                diff_result = await asyncio.to_thread(
                    subprocess.run,
                    ["git", "diff", "HEAD", "--", path],
                    cwd=workdir,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=5,
                )
                patch = diff_result.stdout

            additions, deletions = _count_diff_lines(patch)

            # Truncate if we're over budget
            patch_bytes = len(patch.encode("utf-8", errors="replace"))
            if total_patch_bytes + patch_bytes > MAX_PATCH_BYTES:
                patch = f"(patch truncated — {patch_bytes:,} bytes)"

            total_patch_bytes += patch_bytes

            files.append({
                "path": path,
                "status": file_status,
                "additions": additions,
                "deletions": deletions,
                "patch": patch,
            })

        # Build summary line
        total_adds = sum(f["additions"] for f in files)
        total_dels = sum(f["deletions"] for f in files)
        summary = f"{len(files)} file{'s' if len(files) != 1 else ''} changed"
        if total_adds:
            summary += f", {total_adds} insertion{'s' if total_adds != 1 else ''}(+)"
        if total_dels:
            summary += f", {total_dels} deletion{'s' if total_dels != 1 else ''}(-)"

        return {
            "files": files,
            "summary": summary,
        }

    except Exception:  # noqa: BLE001
        logger.debug("Failed to capture git diff in %s", workdir, exc_info=True)
        return None


def _classify_status(code: str) -> str:
    """Map a git porcelain status code to a human-friendly status."""
    stripped = code.strip()
    if stripped == "??" or stripped.startswith("A"):
        return "added"
    if stripped.startswith("D"):
        return "deleted"
    if stripped.startswith("R"):
        return "renamed"
    return "modified"


def _count_diff_lines(patch: str) -> tuple[int, int]:
    """Count additions and deletions in a unified diff patch."""
    additions = 0
    deletions = 0
    for line in patch.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            additions += 1
        elif line.startswith("-") and not line.startswith("---"):
            deletions += 1
    return additions, deletions


def _read_text(path: Path) -> str | None:
    """Return UTF-8 text for a path, or None if unreadable or missing."""
    try:
        return path.read_text(encoding="utf-8")
    except (FileNotFoundError, IsADirectoryError, UnicodeDecodeError, OSError):
        return None


def _path_changed(workdir: str, path: str, pre: WorktreeSnapshot, post_entries: dict[str, str]) -> bool:
    """Return True when the path's filesystem outcome changed since the snapshot."""
    pre_code = pre.entries.get(path)
    post_code = post_entries.get(path)
    if pre_code != post_code:
        return True
    if path not in pre.before_text:
        return False
    before = pre.before_text[path]
    after = _read_text(Path(workdir) / path)
    return before != after


def _diff_from_snapshot(path: str, before: str | None, after: str | None) -> str:
    """Build a unified diff between the snapshot contents and current contents."""
    diff = difflib.unified_diff(
        [] if before is None else before.splitlines(keepends=True),
        [] if after is None else after.splitlines(keepends=True),
        fromfile=f"a/{path}",
        tofile=f"b/{path}",
    )
    return "".join(diff)
