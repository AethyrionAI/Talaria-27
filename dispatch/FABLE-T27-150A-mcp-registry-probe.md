# FABLE-T27-150A — MCP client Lane A: server registry, settings UX, SDK dependency, honest probe

**Item:** OPEN_ITEMS #150 (✨), Lane A of `design/MCP_CLIENT_DESIGN.md` (READ IT FIRST — it
is binding) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main (≥ `c81500f`)
**Branch:** `claude/t27-150a-mcp-registry-probe` · **Size:** medium, one PR
**Staleness check (2026-07-20 late):** no prior #150 implementation exists. Sole open PR is
#128 (`probe/t27-130-halfduplex`, DO-NOT-MERGE voice probe) — zero file overlap. NOTE:
OPEN_ITEMS numbers ≠ GitHub issue/PR numbers.

## Mission

The foundation lane: users can register MCP servers, store credentials safely, and see an
honest connection state. NO tool execution, NO model wiring, NO chat-plane changes. This
lane also deliberately front-loads the build risk: the SPM dependency on the official
Swift MCP SDK and its first compile against the iOS-27-beta toolchain.

## Deliverables

### D1 — SPM dependency (own commit, first)
`project.yml`: add to the existing `packages:` block (WebRTC shows the pattern):
`MCP: { url: https://github.com/modelcontextprotocol/swift-sdk.git, from: 0.11.0 }`
and add the package product to the Talaria target `dependencies:`. This requires
`xcodegen generate` — pbxproj regen is its OWN separate commit, and per the standing
trap you must verify `aps-environment: development` survives in the entitlements after
regen (it is declared in project.yml precisely to survive; confirm anyway).
If the SDK fails to compile on the 27-beta toolchain or fights the app's Swift 6
region-isolation settings: STOP, document the exact error in the PR description, and
do not write workaround code — the loop decides (pin older tag vs escalate).

### D2 — `Talaria/Services/Support/MCPServerRegistry.swift`
`@Observable` registry of `MCPServerConfig` entries: `id: UUID`, `name: String`,
`url: URL`, `enabled: Bool`, `hasToken: Bool` (derived). Non-secret metadata persists
in UserDefaults under one key (single-blob write, versioned envelope — the #104 lesson:
never per-field writes on hot paths; this list is small and cold, one blob is fine).
Bearer token per server via `KeychainSecureStore`, key naming profile-scoped in the
`BackendProfileScopedKeys` style so a paired-profile wipe removes MCP credentials.
CRUD + `token(for:)` / `setToken(_:for:)`. No networking in this type.

### D3 — `Talaria/Services/Support/MCPProbeService.swift`
Two-step honest probe per design §3:
- Step 1: HTTP reachability against the server URL (short timeout ~5s, HEAD or POST;
  any HTTP response counts as reachable — MCP endpoints may 4xx a bare request).
- Step 2: SDK `Client` + `HTTPClientTransport` (auth via `requestModifier` adding
  `Authorization: Bearer <token>` when a token exists) → `initialize` → `listTools()`;
  capture tool count. Disconnect cleanly.
- Pure classifier `classifyMCPProbe(reachable:initializeOK:authFailed:toolCount:)` →
  `.unreachable / .noAuth / .online(toolCount:)` — a static/pure function exactly like
  the #114 shim classifier so tests never touch the network.
- Probe runs ONLY on demand (screen entry, explicit refresh). Never at app launch
  (#136 posture).

### D4 — `Talaria/Features/Settings/MCPServersScreen.swift`
List of registered servers with probe-state badges (UNREACHABLE / NO AUTH /
ONLINE · n tools — same visual language as the gateway/shim rows in
`ServerSettingsScreen`); add/edit sheet (name, URL, optional bearer token with the
token field masked); delete with confirmation; per-server enabled toggle. Entry point:
a row in the existing server-settings area (match its navigation pattern; read
`ServerSettingsScreen.swift` for the house style before writing UI). No design-system
invention — reuse existing components/tints.

### D5 — Tests
`MCPClientTests.swift` (new test file → remember the regen rule): registry CRUD +
persistence round-trip (UserDefaults suite injected, Keychain faked behind the store's
existing test seam); classifier truth table (all four states incl. auth-failed);
config codable round-trip. UI smoke only if the house pattern supports it cheaply.
Swift Testing (`@Test`) per current suites; note the separate reporting line when
counting.

## Hard constraints
- Files touched: `project.yml` (+regen), the four new Swift files above, and the
  generated pbxproj. NOTHING else. No ChatStore, no ChatBackendRouter, no DeviceTools.
- **Do NOT touch `OPEN_ITEMS.md`** — hard fail; the Mac loop records verdicts.
- New source + test files ⇒ `xcodegen generate` required; regen commit separate;
  re-verify `aps-environment` post-regen.
- File-scoped commits; PR against main; loop merges with a merge commit (never squash).
- Where the SDK's actual API differs from the design's sketch (method names, transport
  init), FOLLOW THE SDK and note the delta in the PR description — do not invent APIs.

## DoD
- PR open; CLI build green on the Mac loop; suite green (baseline 931/84 grows).
- Device pass (loop-owed, not yours): add a server (the Mac gateway URL is a valid
  probe target for reachability; a real MCP server for step 2 if available) → honest
  badge transitions; kill/relaunch → registry persists; profile wipe → token gone.
