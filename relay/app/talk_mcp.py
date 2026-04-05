"""MCP endpoint for voice mode tool delegation.

Implements the MCP Streamable HTTP protocol directly for a single tool:
``hermes_delegate``.  OpenAI's Realtime API calls this server-side during
voice sessions to delegate requests to the Hermes agent.
"""

from __future__ import annotations

import json
import logging
import uuid
from urllib.parse import parse_qs

from fastapi import Request, Response
from fastapi import FastAPI
from fastapi.responses import JSONResponse, StreamingResponse

from .services import get_voice_session_for_tool_token, record_voice_turn

logger = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
#  Tool definition
# --------------------------------------------------------------------------- #

HERMES_DELEGATE_TOOL = {
    "name": "hermes_delegate",
    "description": (
        "Delegate a voice request to the connected Hermes host. "
        "Use this when the user asks for something that requires "
        "tool access, file reads, memory lookups, or any action "
        "beyond what your cached context provides."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "prompt": {
                "type": "string",
                "description": "The natural-language request to send to Hermes.",
            },
        },
        "required": ["prompt"],
    },
}

MCP_SERVER_INFO = {"name": "hermes-mobile-talk", "version": "1.0.0"}
MCP_CAPABILITIES = {"tools": {"listChanged": False}}


# --------------------------------------------------------------------------- #
#  JSON-RPC helpers
# --------------------------------------------------------------------------- #

def _ok(id, result):
    return {"jsonrpc": "2.0", "id": id, "result": result}


def _err(id, code, message):
    return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


# --------------------------------------------------------------------------- #
#  Register MCP routes on the relay FastAPI app
# --------------------------------------------------------------------------- #

def register_talk_mcp_routes(app: FastAPI) -> None:
    """Add the /v1/talk/mcp endpoint directly to the FastAPI app."""

    @app.api_route("/v1/talk/mcp", methods=["GET", "POST"])
    @app.api_route("/v1/talk/mcp/", methods=["GET", "POST"])
    async def talk_mcp_endpoint(request: Request) -> Response:
        # -- Authenticate via query-string token --------------------------
        relay_tool_token = request.query_params.get("token")
        if not relay_tool_token:
            return JSONResponse({"error": "Missing talk tool token."}, status_code=401)

        with app.state.database.session() as db:
            voice_session = get_voice_session_for_tool_token(db, relay_tool_token=relay_tool_token)
        if voice_session is None:
            return JSONResponse({"error": "Invalid or expired talk tool token."}, status_code=401)

        user_id = voice_session.user_id

        # -- GET = SSE stream for server-to-client notifications ------------
        if request.method == "GET":
            async def _sse_keepalive():
                """Hold the SSE connection open for the MCP protocol.

                OpenAI's MCP client opens this to receive server notifications.
                We don't send any, but the connection must stay open for the
                protocol to consider the session healthy.
                """
                import asyncio
                # Send an initial comment to establish the SSE stream
                yield ": connected\n\n"
                try:
                    # Keep alive until the client disconnects
                    while True:
                        await asyncio.sleep(15)
                        yield ": keepalive\n\n"
                except asyncio.CancelledError:
                    return

            return StreamingResponse(
                _sse_keepalive(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "Mcp-Session-Id": voice_session.id,
                },
            )

        # -- POST = JSON-RPC ---------------------------------------------
        try:
            raw = await request.body()
            body = json.loads(raw) if raw else {}
        except (json.JSONDecodeError, ValueError):
            return JSONResponse(_err(None, -32700, "Parse error"), status_code=400)

        # Session ID — use the voice session ID as a stable session token.
        session_id = voice_session.id

        # Handle batch requests
        if isinstance(body, list):
            responses = []
            for item in body:
                resp = await _handle(item, app=app, voice_session=voice_session, user_id=user_id)
                if resp is not None:
                    responses.append(resp)
            if not responses:
                return Response(status_code=204)
            return JSONResponse(
                responses,
                headers={"Mcp-Session-Id": session_id},
            )

        # Single request
        response = await _handle(body, app=app, voice_session=voice_session, user_id=user_id)
        if response is None:
            return Response(status_code=204)

        return JSONResponse(
            response,
            headers={"Mcp-Session-Id": session_id},
        )


async def _handle(body: dict, *, app: FastAPI, voice_session, user_id: str) -> dict | None:
    """Route a single JSON-RPC request."""
    method = body.get("method", "")
    req_id = body.get("id")
    params = body.get("params", {})

    if method == "initialize":
        return _ok(req_id, {
            "protocolVersion": "2025-03-26",
            "serverInfo": MCP_SERVER_INFO,
            "capabilities": MCP_CAPABILITIES,
        })

    if method == "notifications/initialized":
        return None

    if method == "tools/list":
        return _ok(req_id, {"tools": [HERMES_DELEGATE_TOOL]})

    if method == "tools/call":
        return await _handle_tools_call(
            params, req_id=req_id, app=app,
            voice_session=voice_session, user_id=user_id,
        )

    if method == "ping":
        return _ok(req_id, {})

    return _err(req_id, -32601, f"Method not found: {method}")


async def _handle_tools_call(
    params: dict, *, req_id, app: FastAPI, voice_session, user_id: str,
) -> dict:
    tool_name = params.get("name", "")
    arguments = params.get("arguments", {})

    if tool_name != "hermes_delegate":
        return _err(req_id, -32601, f"Unknown tool: {tool_name}")

    prompt = arguments.get("prompt", "").strip()
    if not prompt:
        return _err(req_id, -32602, "Missing required argument: prompt")

    try:
        # Record user turn
        with app.state.database.session() as db:
            record_voice_turn(
                db,
                voice_session_id=voice_session.id,
                role="user",
                source="tool",
                text=prompt,
            )

        # Delegate to the Hermes agent via the connector
        result = await app.state.send_connector_rpc(
            user_id,
            method="talk.delegate",
            params={
                "voiceSessionId": voice_session.id,
                "prompt": prompt,
            },
            timeout_seconds=app.state.settings.talk_delegate_timeout_seconds,
        )

        text = str(result.get("text") or "").strip()

        # Record assistant turn
        with app.state.database.session() as db:
            record_voice_turn(
                db,
                voice_session_id=voice_session.id,
                role="assistant",
                source="tool",
                text=text or "Hermes returned an empty delegation result.",
            )

        return _ok(req_id, {
            "content": [{"type": "text", "text": text}],
            "isError": False,
        })
    except Exception as exc:
        logger.exception("hermes_delegate failed")
        return _ok(req_id, {
            "content": [{"type": "text", "text": f"Delegation failed: {exc}"}],
            "isError": True,
        })
