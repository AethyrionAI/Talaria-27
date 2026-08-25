#!/bin/bash
# agents-md-sync.sh — regenerate AGENTS.md (the Codex rules file) from CLAUDE.md.
#
# Tracker #403. AGENTS.md was measured at its 2026-08-18 creation to be
# CLAUDE.md under a mechanical name swap with ZERO content of its own — and it
# then drifted six days because nothing re-ran the swap. This script IS the
# swap, made deterministic:
#
#   1. the on-disk path `~/Documents/Claude/Talaria` is protected (the original
#      hand swap corrupted it to `~/Documents/Codex/Talaria`, bar 403-C);
#   2. "Claude / Claude Code" (the intro's product pair) becomes plain "Codex";
#   3. the filename CLAUDE.md becomes AGENTS.md;
#   4. every remaining "Claude" becomes "Codex".
#
# Usage:
#   scripts/agents-md-sync.sh           regenerate AGENTS.md in place
#   scripts/agents-md-sync.sh --check   verify AGENTS.md matches (bar 403-B);
#                                       exit 1 + diff on drift
#
# NOT wired into any gate, CI, or procedure — adopting that is Owen's decision
# (#403's Questions-for-Owen block). Until then it is a hand tool.
set -euo pipefail
cd "$(dirname "$0")/.."

generate() {
    sed -e 's|Documents/Claude/Talaria|@@CLAUDE_DISK_PATH@@|g' \
        -e 's|Claude / Claude Code|Codex|g' \
        -e 's/CLAUDE\.md/AGENTS.md/g' \
        -e 's/Claude/Codex/g' \
        -e 's|@@CLAUDE_DISK_PATH@@|Documents/Claude/Talaria|g' \
        CLAUDE.md
}

if [[ "${1:-}" == "--check" ]]; then
    if diff -u <(generate) AGENTS.md; then
        echo "AGENTS-SYNC: IN SYNC (AGENTS.md matches CLAUDE.md under the #403 transform)"
    else
        echo "AGENTS-SYNC: DRIFTED — regenerate with scripts/agents-md-sync.sh" >&2
        exit 1
    fi
else
    generate > AGENTS.md
    echo "AGENTS-SYNC: REGENERATED AGENTS.md from CLAUDE.md"
fi
