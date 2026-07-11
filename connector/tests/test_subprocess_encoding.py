"""Guard against the Windows cp1252 subprocess decode bug.

On Windows, ``subprocess.run(..., text=True)`` without an ``encoding=``
argument decodes the child's pipes with the locale codepage (cp1252 on
OJAMD). ``hermes`` prints UTF-8 — box-drawing characters (``─`` = e2 94 80),
em-dashes, etc. — so the reader thread raised UnicodeDecodeError and the
child's output was silently lost. Every connector subprocess call that
captures text must therefore pin ``encoding="utf-8", errors="replace"``.

These tests are platform-independent by design: CI runs on Linux/UTF-8
where the locale default would mask the bug, so we audit the source
statically and force the exact bad bytes through the real decode path
instead of relying on the OS default.
"""

from __future__ import annotations

import ast
from pathlib import Path
import subprocess
import sys

import hermes_mobile_connector
from hermes_mobile_connector import talk_support

PACKAGE_DIR = Path(hermes_mobile_connector.__file__).parent

SUBPROCESS_FUNCS = {"run", "Popen", "check_output", "check_call", "call"}


def _subprocess_call_nodes(tree: ast.AST):
    """Yield every Call node that invokes subprocess.<func>.

    Covers both direct calls (``subprocess.run(...)``) and the deferred form
    used in git_diff.py (``asyncio.to_thread(subprocess.run, ...)``), where
    the subprocess kwargs live on the outer call.
    """
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if (
            isinstance(func, ast.Attribute)
            and isinstance(func.value, ast.Name)
            and func.value.id == "subprocess"
            and func.attr in SUBPROCESS_FUNCS
        ):
            yield node
        elif (
            node.args
            and isinstance(node.args[0], ast.Attribute)
            and isinstance(node.args[0].value, ast.Name)
            and node.args[0].value.id == "subprocess"
            and node.args[0].attr in SUBPROCESS_FUNCS
        ):
            yield node


def _keyword_constants(node: ast.Call) -> dict[str, object]:
    return {
        kw.arg: kw.value.value
        for kw in node.keywords
        if kw.arg is not None and isinstance(kw.value, ast.Constant)
    }


def test_every_text_mode_subprocess_call_pins_utf8() -> None:
    violations = []
    for source_file in sorted(PACKAGE_DIR.rglob("*.py")):
        tree = ast.parse(source_file.read_text(encoding="utf-8"))
        for node in _subprocess_call_nodes(tree):
            kwargs = _keyword_constants(node)
            wants_text = (
                kwargs.get("text") is True
                or kwargs.get("universal_newlines") is True
            )
            if not wants_text:
                continue
            if kwargs.get("encoding") != "utf-8" or kwargs.get("errors") != "replace":
                violations.append(
                    f"{source_file.relative_to(PACKAGE_DIR)}:{node.lineno}"
                )
    assert not violations, (
        "text-mode subprocess calls missing encoding='utf-8', errors='replace' "
        f"(Windows decodes pipes as cp1252 without it): {violations}"
    )


def test_memory_status_survives_hermes_utf8_output(monkeypatch) -> None:
    """Round-trip the exact bytes from the OJAMD failure through a real pipe.

    The payload carries the box-drawing char (e2 94 80) plus a stray 0x90 —
    the byte cp1252 chokes on, which is also invalid standalone UTF-8, so
    without the pinned encoding+errors this raises on any platform.
    """
    payload = b"provider: qdrant \x90 \xe2\x94\x80 ok\nstatus: ready\n"
    captured_kwargs: dict[str, object] = {}
    real_run = subprocess.run

    def spy_run(command, **kwargs):
        captured_kwargs.update(kwargs)
        script = f"import sys; sys.stdout.buffer.write({payload!r})"
        return real_run([sys.executable, "-c", script], **kwargs)

    monkeypatch.setattr(talk_support.subprocess, "run", spy_run)
    monkeypatch.setattr(talk_support, "_memory_provider_cache", (0.0, ""))

    result = talk_support.summarize_memory_provider(
        hermes_command="hermes", hermes_home=None
    )

    assert captured_kwargs.get("encoding") == "utf-8"
    assert captured_kwargs.get("errors") == "replace"
    assert "unavailable" not in result.lower()
    assert "─ ok" in result  # box-drawing char decoded, not mangled
    assert "�" in result  # invalid byte replaced instead of raising
