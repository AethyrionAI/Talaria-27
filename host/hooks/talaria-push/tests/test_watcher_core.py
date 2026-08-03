# Tests for the talaria-push watcher core (OPEN_ITEMS #223, push v1).
# The module under test is dependency-free on purpose — any Python >=3.11
# with pytest runs these.
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from watcher_core import (ApnsTokenPolicy, WatcherState, build_apns_request,
                          extract_completion)


def _u(mid, text="hi"):
    return {"id": mid, "role": "user", "content": text}


def _a(mid, text="reply"):
    return {"id": mid, "role": "assistant", "content": text}


def test_completion_is_assistant_after_last_user():
    assert extract_completion([_u(1), _a(2)]) == (2, "reply")


def test_no_user_message_means_none():
    assert extract_completion([_a(1)]) is None


def test_pending_run_means_none():
    # user spoke last — run not finished
    assert extract_completion([_u(1), _a(2), _u(3)]) is None


def test_empty_assistant_does_not_complete():
    # tool-call shells have empty content (seen live 2026-08-02)
    assert extract_completion([_u(1), _a(2, ""), _a(3, "real")]) == (3, "real")


def test_structured_content_parts_extracted():
    msgs = [_u(1), {"id": 2, "role": "assistant",
                    "content": [{"type": "text", "text": "part"}]}]
    assert extract_completion(msgs) == (2, "part")


def test_first_sight_primes_silently():
    st = WatcherState()
    # A session first seen ALREADY completed must not ping (gateway restart case).
    assert st.completions_to_ping("s1", [_u(1), _a(2)]) == []


def test_new_completion_after_priming_pings_once():
    st = WatcherState()
    st.completions_to_ping("s1", [_u(1), _a(2)])          # prime
    st.completions_to_ping("s1", [_u(1), _a(2), _u(3)])   # run pending
    assert st.completions_to_ping("s1", [_u(1), _a(2), _u(3), _a(4)]) == [4]
    # same transcript again: no re-ping
    assert st.completions_to_ping("s1", [_u(1), _a(2), _u(3), _a(4)]) == []


def test_sessions_are_independent():
    st = WatcherState()
    st.completions_to_ping("s1", [_u(1), _a(2)])
    assert st.completions_to_ping("s2", [_u(1), _a(2)]) == []  # s2 primes separately


def test_apns_request_shape():
    url, headers, payload = build_apns_request(
        "abc123", "api_555", topic="org.aethyrion.talaria27",
        environment="sandbox", title="Hermes", body="Reply ready")
    assert url == "https://api.sandbox.push.apple.com/3/device/abc123"
    assert headers["apns-topic"] == "org.aethyrion.talaria27"
    assert headers["apns-push-type"] == "alert"
    assert payload["session_id"] == "api_555"          # #38 payload contract
    assert payload["aps"]["alert"]["body"] == "Reply ready"


def test_production_host():
    url, _, _ = build_apns_request("t", "s", topic="x", environment="production",
                                   title="a", body="b")
    assert url.startswith("https://api.push.apple.com/")


def test_token_reused_inside_window():
    calls = []
    pol = ApnsTokenPolicy(mint=lambda: calls.append(1) or f"tok{len(calls)}",
                          now=lambda: 1000.0)
    assert pol.token() == "tok1"
    pol._now = lambda: 1000.0 + 40 * 60          # 40 min later
    assert pol.token() == "tok1"                  # reused
    pol._now = lambda: 1000.0 + 51 * 60          # past 50-min refresh
    assert pol.token() == "tok2"
