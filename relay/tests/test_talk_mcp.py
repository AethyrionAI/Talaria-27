"""#85: talk MCP URL construction + advertise gating.

The relay hands OpenAI's Realtime API an MCP server URL at voice-session
mint. Two failure classes are covered here:

- path drift: the endpoint mounts at the literal ``/v1/talk/mcp``, while
  ``PUBLIC_BASE_URL`` may or may not carry the ``/v1`` suffix — the built
  URL must match the mounted route either way;
- unreachable base: OpenAI fetches the tool list from *its* servers, so a
  loopback/LAN/Tailscale base URL must not be advertised at all.
"""

from __future__ import annotations

from app.services import build_talk_mcp_url, should_advertise_talk_mcp


# --------------------------------------------------------------------------- #
#  build_talk_mcp_url — always lands on the mounted /v1/talk/mcp route
# --------------------------------------------------------------------------- #

def test_mcp_url_with_versioned_base():
    url = build_talk_mcp_url("https://relay.example.test/v1", token="tok-1")
    assert url == "https://relay.example.test/v1/talk/mcp?token=tok-1"


def test_mcp_url_with_bare_base_gains_v1():
    url = build_talk_mcp_url("https://relay.example.test", token="tok-2")
    assert url == "https://relay.example.test/v1/talk/mcp?token=tok-2"


def test_mcp_url_with_trailing_slash_does_not_double_path():
    assert (
        build_talk_mcp_url("https://relay.example.test/v1/", token="t")
        == "https://relay.example.test/v1/talk/mcp?token=t"
    )
    assert (
        build_talk_mcp_url("https://relay.example.test/", token="t")
        == "https://relay.example.test/v1/talk/mcp?token=t"
    )


def test_mcp_url_preserves_port_and_encodes_token():
    url = build_talk_mcp_url("http://100.110.102.59:8000/v1", token="a/b+c")
    assert url == "http://100.110.102.59:8000/v1/talk/mcp?token=a%2Fb%2Bc"


# --------------------------------------------------------------------------- #
#  should_advertise_talk_mcp — auto mode keys off public reachability
# --------------------------------------------------------------------------- #

def test_auto_skips_loopback_and_private_and_tailscale():
    for base in (
        "http://127.0.0.1:8000/v1",
        "http://localhost:8000/v1",
        "http://10.0.0.5:8000/v1",
        "http://192.168.1.20:8000/v1",
        "http://172.16.9.1:8000/v1",
        # Tailscale hands out RFC 6598 CGNAT space (100.64/10) — OJAMD's
        # tailnet IP lives here and OpenAI's servers can never route to it.
        "http://100.110.102.59:8000/v1",
    ):
        assert should_advertise_talk_mcp(base, mode="auto") is False, base


def test_auto_skips_mdns_hostnames():
    assert should_advertise_talk_mcp("http://ojamd.local:8000/v1", mode="auto") is False


def test_auto_advertises_public_hosts():
    assert should_advertise_talk_mcp("https://relay.example.test/v1", mode="auto") is True
    assert should_advertise_talk_mcp("https://relay.example.test", mode="auto") is True
    # A public IP literal is globally routable.
    assert should_advertise_talk_mcp("https://8.8.8.8/v1", mode="auto") is True


def test_always_and_never_override_auto_detection():
    tailnet = "http://100.110.102.59:8000/v1"
    public = "https://relay.example.test/v1"
    assert should_advertise_talk_mcp(tailnet, mode="always") is True
    assert should_advertise_talk_mcp(public, mode="never") is False
    # Mode strings are trimmed + case-insensitive (env-sourced).
    assert should_advertise_talk_mcp(tailnet, mode=" ALWAYS ") is True


def test_blank_or_unknown_mode_falls_back_to_auto():
    tailnet = "http://100.110.102.59:8000/v1"
    public = "https://relay.example.test/v1"
    assert should_advertise_talk_mcp(tailnet, mode="") is False
    assert should_advertise_talk_mcp(public, mode="") is True
