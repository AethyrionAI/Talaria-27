from __future__ import annotations

import argparse
import asyncio
import getpass
import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

import httpx
import qrcode

from .client import HermesMobileConnector
from .service_management import build_service_manager


def prompt(label: str, *, default: str | None = None, optional: bool = False) -> str | None:
    """Prompt the user interactively. Returns None only when optional and blank."""
    suffix = f" [{default}]" if default else ""
    suffix += " (optional)" if optional and not default else ""
    response = input(f"{label}{suffix}: ").strip()
    if response:
        return response
    if default:
        return default
    if optional:
        return None
    raise SystemExit(f"{label} is required.")


def confirm(question: str, *, default: bool = True) -> bool:
    hint = "Y/n" if default else "y/N"
    response = input(f"{question} [{hint}] ").strip().lower()
    if not response:
        return default
    return response in ("y", "yes")


def choose_option(question: str, options: dict[str, str], *, default: str) -> str:
    print(question)
    for key, description in options.items():
        suffix = " (default)" if key == default else ""
        print(f"  {key}. {description}{suffix}")

    response = input(f"Choose [{default}]: ").strip()
    if not response:
        return default
    if response not in options:
        raise SystemExit(f"Unsupported choice: {response}")
    return response


def validate_relay_health(relay_url: str) -> bool:
    """Check if a relay is reachable and healthy."""
    try:
        resp = httpx.get(f"{relay_url.rstrip('/')}/health", timeout=10.0)
        return resp.status_code == 200
    except Exception:
        return False


def _find_relay_source_dir() -> Path | None:
    """Locate the relay/ directory relative to the connector package."""
    # connector/src/hermes_mobile_connector/cli.py → repo/relay/
    candidate = Path(__file__).resolve().parent.parent.parent.parent / "relay"
    if (candidate / "app" / "main.py").exists():
        return candidate
    return None


def _find_flyctl() -> str | None:
    """Find the flyctl binary."""
    for name in ("flyctl", "fly"):
        path = shutil.which(name)
        if path:
            return path
    return None


def _run_fly(
    flyctl: str,
    args: list[str],
    *,
    cwd: str | Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    """Run a flyctl command, printing output live.

    Raises subprocess.CalledProcessError on non-zero exit when check=True (default).
    """
    return subprocess.run(
        [flyctl, *args],
        cwd=cwd,
        text=True,
        check=check,
    )


def _resolve_mpg_cluster_id(flyctl: str, cluster_name: str) -> str | None:
    """Resolve a Managed Postgres cluster ID from its name via fly mpg list.

    Returns the cluster ID string, or None if not found.
    """
    try:
        result = subprocess.run(
            [flyctl, "mpg", "list", "--json"],
            capture_output=True, text=True, check=True,
        )
        import json
        clusters = json.loads(result.stdout)
        if isinstance(clusters, list):
            for cluster in clusters:
                if cluster.get("name") == cluster_name:
                    return cluster.get("id") or cluster.get("ID")
        # If --json isn't supported, try parsing text output
    except (subprocess.CalledProcessError, json.JSONDecodeError, Exception):
        pass

    # Fallback: try fly mpg list without --json and parse the table
    try:
        result = subprocess.run(
            [flyctl, "mpg", "list"],
            capture_output=True, text=True, check=True,
        )
        for line in result.stdout.splitlines():
            if cluster_name in line:
                # Table format usually has ID as the first column
                parts = line.split()
                if parts:
                    return parts[0]
    except Exception:
        pass

    return None


def deploy_relay_to_fly() -> tuple[str, str]:
    """Guided Fly.io relay deployment. Returns (relay_url, setup_secret)."""
    print()

    # 1. Check flyctl
    flyctl = _find_flyctl()
    if not flyctl:
        print("flyctl is not installed.")
        print("Install it from: https://fly.io/docs/flyctl/install/")
        print("Then run this setup again.")
        raise SystemExit(1)
    print(f"Found flyctl: {flyctl}")

    # 2. Check auth
    result = subprocess.run([flyctl, "auth", "whoami"], capture_output=True, text=True)
    if result.returncode != 0:
        print("Not logged in to Fly.io. Launching login...")
        _run_fly(flyctl, ["auth", "login"])

    # 3. App name
    default_user = os.getenv("USER") or getpass.getuser() or "user"
    default_app = f"hermes-relay-{default_user}".lower().replace("_", "-")
    app_name = prompt("Fly app name", default=default_app)

    # 4. Region
    region = prompt("Fly region (see https://fly.io/docs/reference/regions/)", default="iad")

    # 5. Generate secrets
    internal_key = secrets.token_hex(16)
    setup_secret = secrets.token_hex(16)
    print(f"\nGenerated INTERNAL_API_KEY: {internal_key[:8]}...")
    print(f"Generated CONNECTOR_SETUP_SECRET: {setup_secret[:8]}...")

    # 6. Find relay source
    relay_dir = _find_relay_source_dir()
    if relay_dir is None:
        print("\nCould not find relay/ directory. Deploy manually:")
        print("  cd relay && flyctl deploy")
        raise SystemExit(1)

    # 7. Write fly.toml with app name and PUBLIC_BASE_URL
    relay_url = f"https://{app_name}.fly.dev/v1"
    fly_toml = relay_dir / "fly.toml"
    fly_toml_content = fly_toml.read_text()

    # Back up the original
    fly_toml_backup = relay_dir / "fly.toml.bak"
    fly_toml_backup.write_text(fly_toml_content)

    updated = fly_toml_content
    # Replace app name
    import re
    updated = re.sub(r'^app\s*=\s*"[^"]*"', f'app = "{app_name}"', updated, count=1, flags=re.MULTILINE)
    # Replace PUBLIC_BASE_URL
    updated = re.sub(
        r'PUBLIC_BASE_URL\s*=\s*"[^"]*"',
        f'PUBLIC_BASE_URL = "{relay_url}"',
        updated,
        count=1,
    )
    fly_toml.write_text(updated)

    print(f"\nUpdated fly.toml: app={app_name}, PUBLIC_BASE_URL={relay_url}")

    try:
        # 8. Create app
        print(f"\nCreating Fly app: {app_name}...")
        try:
            _run_fly(flyctl, ["apps", "create", app_name])
        except subprocess.CalledProcessError:
            print("  App creation failed — it may already exist. Continuing.")

        # 9. Create Postgres (try Managed Postgres first, fall back to legacy)
        # See: https://fly.io/docs/mpg/create-and-connect/
        db_name = f"{app_name}-db"
        use_managed = False
        print(f"\nCreating Postgres database: {db_name}...")
        print("  Trying Managed Postgres (fly mpg) first...")
        try:
            _run_fly(flyctl, ["mpg", "create", "--name", db_name, "--region", region])
            use_managed = True
            print("  Managed Postgres created.")
        except subprocess.CalledProcessError:
            print("  Managed Postgres not available. Falling back to legacy Fly Postgres...")
            try:
                _run_fly(flyctl, [
                    "postgres", "create",
                    "--name", db_name,
                    "--region", region,
                    "--vm-size", "shared-cpu-1x",
                    "--initial-cluster-size", "1",
                    "--volume-size", "1",
                ])
                print("  Legacy Postgres created.")
            except subprocess.CalledProcessError as e:
                print(f"  ERROR: Postgres creation failed: {e}")
                print("  Create the database manually, then re-run setup:")
                print(f"    fly mpg create --name {db_name} --region {region}")
                raise

        # 10. Attach Postgres
        print(f"\nAttaching database to app...")
        if use_managed:
            # Managed Postgres: fly mpg attach requires the cluster ID, not name.
            # Resolve it from fly mpg list.
            cluster_id = _resolve_mpg_cluster_id(flyctl, db_name)
            if cluster_id:
                try:
                    _run_fly(flyctl, ["mpg", "attach", cluster_id, "-a", app_name])
                    print(f"  Database attached (managed, cluster {cluster_id}).")
                except subprocess.CalledProcessError as e:
                    print(f"  ERROR: Managed attach failed: {e}")
                    print(f"  Attach manually using the cluster ID from 'fly mpg list':")
                    print(f"    fly mpg attach <CLUSTER_ID> -a {app_name}")
                    raise
            else:
                print(f"  WARNING: Could not resolve cluster ID for '{db_name}'.")
                print(f"  Run 'fly mpg list' to find the cluster ID, then attach manually:")
                print(f"    fly mpg attach <CLUSTER_ID> -a {app_name}")
        else:
            # Legacy Postgres: attach by app name
            try:
                _run_fly(flyctl, ["postgres", "attach", db_name, "-a", app_name])
                print("  Database attached (legacy).")
            except subprocess.CalledProcessError as e:
                print(f"  ERROR: Database attach failed: {e}")
                print(f"  Attach manually:")
                print(f"    fly postgres attach {db_name} -a {app_name}")
                raise

        # 11. Set secrets
        print("\nSetting secrets...")
        _run_fly(flyctl, [
            "secrets", "set",
            f"INTERNAL_API_KEY={internal_key}",
            f"CONNECTOR_SETUP_SECRET={setup_secret}",
            "-a", app_name,
        ])

        # 12. Deploy
        print(f"\nDeploying relay from {relay_dir}...")
        result = _run_fly(flyctl, ["deploy", "-a", app_name], cwd=relay_dir)
        if result.returncode != 0:
            print("Deployment failed. Check the output above.")
            raise SystemExit(1)

        # 13. Wait for health
        print(f"\nWaiting for relay to become healthy at {relay_url}...")
        for attempt in range(30):
            if validate_relay_health(relay_url):
                print("Relay is healthy!")
                break
            import time
            time.sleep(2)
        else:
            print("Relay did not become healthy within 60 seconds.")
            print(f"Check status: flyctl status -a {app_name}")
            print(f"View logs: flyctl logs -a {app_name}")

    finally:
        # Restore original fly.toml so we don't commit personal values
        fly_toml.write_text(fly_toml_content)
        fly_toml_backup.unlink(missing_ok=True)

    return relay_url, setup_secret


def resolve_relay_url(connector: HermesMobileConnector) -> tuple[str, str | None]:
    """Detect or prompt for a relay URL. Returns (relay_url, setup_secret_or_none)."""
    # Check env var first
    existing = connector.default_relay_url()
    if existing:
        print(f"Relay URL (from env): {existing}")
        if validate_relay_health(existing):
            print("Relay is reachable and healthy.")
            return existing, os.getenv("CONNECTOR_SETUP_SECRET")
        else:
            print("Warning: relay is not responding. Continuing anyway...")
            return existing, os.getenv("CONNECTOR_SETUP_SECRET")

    # No relay configured — offer options
    relay_dir = _find_relay_source_dir()
    options: dict[str, str] = {}
    if relay_dir and _find_flyctl():
        options["1"] = "Deploy a new relay on Fly.io (recommended)"
    options["2"] = "Enter an existing relay URL"
    options["3"] = "Use local network relay (simulator or same-network testing)"

    default = "1" if "1" in options else "2"
    choice = choose_option("\nHow would you like to connect to a relay?", options, default=default)

    if choice == "1":
        return deploy_relay_to_fly()

    if choice == "2":
        url = prompt("Relay API base URL (e.g. https://your-relay.fly.dev/v1)")
        if url and validate_relay_health(url):
            print("Relay is reachable and healthy.")
        elif url:
            print("Warning: relay is not responding. Continuing anyway...")
        return url or "", os.getenv("CONNECTOR_SETUP_SECRET")

    # choice == "3" — local network
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "127.0.0.1"
    default_url = f"http://{local_ip}:8000/v1"
    print(f"\nYour local network IP: {local_ip}")
    print("IMPORTANT: 127.0.0.1 does NOT work on physical devices — it resolves to the phone itself.")
    print("Use your Mac's local IP address so the phone can reach the relay over Wi-Fi.")
    url = prompt(f"Relay URL [{default_url}]") or default_url
    return url, None


def print_qr_code(value: str) -> None:
    qr = qrcode.QRCode(border=1)
    qr.add_data(value)
    qr.make(fit=True)
    qr.print_ascii(tty=sys.stdout.isatty())


def print_header(text: str) -> None:
    print(f"\n{'─' * 40}")
    print(f"  {text}")
    print(f"{'─' * 40}\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="hermes-mobile",
        description="Connect your Hermes CLI to Hermes Mobile.",
    )
    subparsers = parser.add_subparsers(dest="command")

    setup = subparsers.add_parser("setup", help="Register this machine with a Hermes Mobile relay.")
    setup.add_argument("--relay-url", help="Relay API base URL. Required unless HERMES_MOBILE_RELAY_URL is set.")
    setup.add_argument(
        "--skip-mcp",
        action="store_true",
        help="Register the host without editing ~/.hermes/config.yaml. You can run `hermes-mobile configure-mcp` later.",
    )

    enroll = subparsers.add_parser("enroll", help="(Legacy) Redeem an HC1 host setup code.")
    enroll.add_argument("--code", required=True, help="HC1 setup code.")
    enroll.add_argument("--display-name", help="Optional label for this Hermes host.")
    enroll.add_argument(
        "--skip-mcp",
        action="store_true",
        help="Redeem the host without editing ~/.hermes/config.yaml. You can run `hermes-mobile configure-mcp` later.",
    )

    subparsers.add_parser(
        "configure-mcp",
        help="Write Hermes Mobile MCP tools into the local Hermes config and validate them.",
    )
    configure_realtime = subparsers.add_parser(
        "configure-realtime",
        help="Add or update the OpenAI Realtime configuration stored on this Hermes host.",
    )
    configure_realtime.add_argument("--clear", action="store_true", help="Remove the stored OpenAI API key and disable talk mode.")
    configure_realtime.add_argument(
        "--skip-validation",
        action="store_true",
        help="Store the API key without validating the Realtime session flow right now.",
    )
    subparsers.add_parser("pair-phone", help="Generate a short-lived phone pairing code and QR.")
    subparsers.add_parser("run", help="Run the long-lived Hermes Mobile connector.")
    subparsers.add_parser("status", help="Show the current connector state.")
    subparsers.add_parser("validate-mcp", help="Verify Hermes can discover the Hermes Mobile MCP tools.")
    subparsers.add_parser("reset", help="Remove local connector state and start fresh.")

    service = subparsers.add_parser("service", help="Manage the connector background service.")
    service_subparsers = service.add_subparsers(dest="service_command")
    install = service_subparsers.add_parser("install", help="Install the background service.")
    install.add_argument("--force", action="store_true", help="Rewrite service artifacts and registration.")
    service_subparsers.add_parser("start", help="Start the background service.")
    service_subparsers.add_parser("stop", help="Stop the background service.")
    service_subparsers.add_parser("restart", help="Restart the background service.")
    service_subparsers.add_parser("status", help="Show background service status.")
    logs = service_subparsers.add_parser("logs", help="Show recent background service logs.")
    logs.add_argument("--lines", type=int, default=100, help="How many lines to show from each log.")
    service_subparsers.add_parser("uninstall", help="Remove the background service registration.")
    return parser


# ── Interactive wizard (no subcommand) ───────────────────────────

def run_wizard(connector: HermesMobileConnector) -> int:
    print_header("Hermes Mobile Connector Setup")

    # Check for existing state
    try:
        existing = connector.state_store.load()
        print(f"This machine is already set up (host {existing.host_id[:8]}...).")
        print()
        if not confirm("Start over with a fresh setup?", default=False):
            return _wizard_post_setup(connector)
        connector.state_store.clear()
        print("Previous state cleared.\n")
    except RuntimeError:
        pass

    # Step 1: Validate Hermes CLI
    print_header("Step 1 of 5 — Verify Hermes CLI")
    metadata = connector.metadata()
    if metadata.hermes_version is None:
        print(f"Could not find Hermes at: {metadata.hermes_command}")
        print("Install Hermes or set HERMES_COMMAND to its path.")
        return 1
    print(f"Found: {metadata.hermes_version}")
    print(f"Command: {metadata.hermes_command}")
    print()

    # Step 2: Connect to a relay
    print_header("Step 2 of 5 — Connect to a Relay")
    relay_url, setup_secret = resolve_relay_url(connector)
    if not relay_url:
        print("Relay URL is required.")
        return 1
    print()

    # If deployment generated a setup secret, set it in the environment
    # so the connector.setup() call includes it
    if setup_secret:
        os.environ["CONNECTOR_SETUP_SECRET"] = setup_secret

    # Step 3: Register
    print_header("Step 3 of 5 — Register This Machine")
    print("Registering this machine with the Hermes Mobile relay...")
    try:
        state = connector.setup(relay_url=relay_url, configure_mcp=False)
    except Exception as e:
        print(f"Setup failed: {e}")
        return 1
    print(f"Account created. Host ID: {state.host_id}")
    print()

    should_configure_mcp = confirm(
        "Automatically configure iOS tools MCP (Location Services, Health, and sensor context) in your Hermes Agent config file?",
        default=True,
    )
    if should_configure_mcp:
        try:
            connector.configure_mcp()
            mcp_lines = connector.validate_mcp()
            print("Native MCP check: ok")
            print(mcp_lines[-1])
        except Exception as e:
            print(f"Native MCP check: warning — {e}")
    else:
        print("Skipped native MCP config.")
        print("You can enable it later with: hermes-mobile configure-mcp")

    should_configure_realtime = confirm(
        "Configure OpenAI Realtime talk mode now?",
        default=True,
    )
    if should_configure_realtime:
        api_key = getpass.getpass("OpenAI API key: ").strip()
        try:
            state = connector.configure_realtime(api_key=api_key, validate=True)
            talk_status = connector.talk_readiness_payload()
            print("Realtime talk check: ok")
            print(f"Selected model: {talk_status['selectedModel'] or 'pending'}")
        except Exception as e:
            print(f"Realtime talk check: warning — {e}")
    else:
        print("Skipped OpenAI Realtime talk setup.")
        print("You can enable it later with: hermes-mobile configure-realtime")

    return _wizard_post_setup(connector)


def _wizard_post_setup(connector: HermesMobileConnector) -> int:
    # Step 4: Phone pairing
    print_header("Step 4 of 5 — Pair Your Phone")
    print("Generate a one-time code for the Hermes Mobile app.\n")

    if not confirm("Generate a phone pairing code now?"):
        print("\nYou can generate one later with: hermes-mobile pair-phone")
        print("Then start the connector with: hermes-mobile run")
        return 0

    try:
        pairing = connector.create_phone_pairing_code()
    except Exception as e:
        print(f"Failed to create pairing code: {e}")
        return 1

    state = connector.state_store.load()
    relay_url = state.relay_url or ""

    print(f"\nYour pairing code:  {pairing.display_code}")
    if relay_url:
        print(f"Relay:              {relay_url}")
    if pairing.expires_at:
        print(f"Expires at:         {pairing.expires_at}")
    print()

    import json
    qr_payload = json.dumps({"code": pairing.code, "relay": relay_url}, separators=(",", ":"))
    print_qr_code(qr_payload)
    print("Open Hermes Mobile on your phone and scan the QR code.")
    print()

    input("Press Enter once your phone is paired...")

    print_header("Step 5 of 5 — Keep Hermes Available")
    service_manager = build_service_manager(connector.state_store)
    service_status = service_manager.status()

    if service_status.supported:
        selection = choose_option(
            "How do you want to run the connector?",
            {
                "1": "Install and start the background service",
                "2": "Install the background service, but do not start it yet",
                "3": "Run in the foreground for development/debugging",
                "4": "Skip for now",
            },
            default="1",
        )

        try:
            connector.refresh_runtime_config(force=False)
            if selection == "1":
                if not service_status.installed:
                    print(service_manager.install(force=False))
                print(service_manager.start())
                return 0
            if selection == "2":
                print(service_manager.install(force=service_status.installed))
                print("Background service installed. Start it later with: hermes-mobile service start")
                return 0
            if selection == "3":
                return _run_foreground(connector)
            print("You can manage the background service later with: hermes-mobile service <install|start|stop|restart|status>")
            print("Or run the connector in the foreground with: hermes-mobile run")
            return 0
        except Exception as error:  # noqa: BLE001
            print(f"Background service setup failed: {error}")
            print("Falling back to foreground instructions.")

    if confirm("Start the connector now in the foreground?"):
        return _run_foreground(connector)

    print("\nStart the connector later with: hermes-mobile run")
    return 0


# ── Individual subcommands ───────────────────────────────────────

def cmd_setup(args: argparse.Namespace, connector: HermesMobileConnector) -> int:
    try:
        existing = connector.state_store.load()
        print(f"Already set up for {existing.relay_url}.")
        print("Run `hermes-mobile reset` to start over.")
        return 1
    except RuntimeError:
        pass

    state = connector.setup(relay_url=args.relay_url, configure_mcp=not args.skip_mcp)
    print(f"Registered. Host: {state.host_id}")
    if args.skip_mcp:
        print("Native MCP config skipped.")
        print("Run `hermes-mobile configure-mcp` when you want to add Hermes Mobile tools to ~/.hermes/config.yaml.")
    elif state.mcp_last_test_error:
        print(f"Native MCP check: warning — {state.mcp_last_test_error}")
    else:
        print("Native MCP check: ok")
    if not args.skip_mcp:
        print(connector.validate_mcp()[-1])
    print("Talk mode stays optional. Run `hermes-mobile configure-realtime` when you want to enable OpenAI Realtime talk mode.")
    print("\nNext: hermes-mobile pair-phone")
    return 0


def cmd_configure_mcp(connector: HermesMobileConnector) -> int:
    state = connector.configure_mcp()
    print(f"Configured Hermes Mobile MCP for host {state.host_id}")
    for line in connector.validate_mcp():
        print(line)
    return 0


def cmd_configure_realtime(args: argparse.Namespace, connector: HermesMobileConnector) -> int:
    if args.clear:
        state = connector.configure_realtime(clear=True, validate=False)
        print(f"Cleared OpenAI Realtime config for host {state.host_id}")
        return 0

    api_key = getpass.getpass("OpenAI API key: ").strip()
    state = connector.configure_realtime(api_key=api_key, validate=not args.skip_validation)
    print(f"Configured OpenAI Realtime for host {state.host_id}")
    talk_status = connector.talk_readiness_payload()
    print(f"Realtime talk: {'configured' if talk_status['configured'] else 'not configured'}")
    if talk_status["selectedModel"]:
        print(f"Selected model: {talk_status['selectedModel']}")
    if talk_status["lastValidationError"]:
        print(f"Validation: {talk_status['lastValidationError']}")
    return 0


def cmd_enroll(args: argparse.Namespace, connector: HermesMobileConnector) -> int:
    state = connector.enroll(
        code=args.code,
        display_name=args.display_name,
        configure_mcp=not args.skip_mcp,
    )
    print(f"Enrolled host {state.host_id} against {state.relay_url}")
    if args.skip_mcp:
        print("Native MCP config skipped. Run `hermes-mobile configure-mcp` later if you want Hermes Mobile tools in Hermes.")
    print("Run `hermes-mobile configure-realtime` when you want to enable OpenAI Realtime talk mode.")
    return 0


def cmd_pair_phone(connector: HermesMobileConnector) -> int:
    pairing = connector.create_phone_pairing_code()
    state = connector.state_store.load()
    relay_url = state.relay_url or ""

    print(f"\nPairing code:  {pairing.display_code}")
    if relay_url:
        print(f"Relay:         {relay_url}")
    if pairing.expires_at:
        print(f"Expires at:    {pairing.expires_at}")
    print()

    # QR encodes a JSON payload so the iOS app gets both relay URL and code in one scan
    import json
    qr_payload = json.dumps({"code": pairing.code, "relay": relay_url}, separators=(",", ":"))
    print_qr_code(qr_payload)
    print("Open Hermes Mobile on your phone and scan the QR code.")
    print(f"Or enter the code manually: {pairing.display_code}")
    return 0


def cmd_run(connector: HermesMobileConnector) -> int:
    return _run_foreground(connector)


def cmd_status(connector: HermesMobileConnector) -> int:
    for line in connector.status_lines():
        print(line)
    return 0


def cmd_validate_mcp(connector: HermesMobileConnector) -> int:
    for line in connector.validate_mcp():
        print(line)
    return 0


def cmd_reset(connector: HermesMobileConnector) -> int:
    try:
        connector.state_store.load()
    except RuntimeError:
        print("No connector state found. Nothing to reset.")
        return 0

    if not confirm("Remove all local connector state? This cannot be undone."):
        print("Cancelled.")
        return 0

    connector.state_store.clear()
    print("Connector state removed. Run `hermes-mobile` to set up again.")
    return 0


def cmd_service(args: argparse.Namespace, connector: HermesMobileConnector) -> int:
    manager = build_service_manager(connector.state_store)
    action = args.service_command

    if action == "install":
        connector.refresh_runtime_config(force=args.force)
        print(manager.install(force=args.force))
        return 0
    if action == "start":
        print(manager.start())
        return 0
    if action == "stop":
        print(manager.stop())
        return 0
    if action == "restart":
        print(manager.restart())
        return 0
    if action == "status":
        status = manager.status()
        print(f"Backend: {status.backend}")
        print(f"Installed: {'yes' if status.installed else 'no'}")
        print(f"Running: {'yes' if status.running else 'no'}")
        print(f"Detail: {status.detail}")
        print(f"Stdout log: {status.stdout_log}")
        print(f"Stderr log: {status.stderr_log}")
        return 0
    if action == "logs":
        print(manager.logs(lines=args.lines))
        return 0
    if action == "uninstall":
        print(manager.uninstall())
        return 0

    raise SystemExit("Service command is required.")


def _run_foreground(connector: HermesMobileConnector) -> int:
    print("Connector running. Press Ctrl+C to stop.\n")
    asyncio.run(connector.run_forever())
    return 0


# ── Entry point ──────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    connector = HermesMobileConnector()

    if args.command is None:
        return run_wizard(connector)

    if args.command == "setup":
        return cmd_setup(args, connector)
    if args.command == "configure-mcp":
        return cmd_configure_mcp(connector)
    if args.command == "configure-realtime":
        return cmd_configure_realtime(args, connector)
    if args.command == "enroll":
        return cmd_enroll(args, connector)
    if args.command == "pair-phone":
        return cmd_pair_phone(connector)
    if args.command == "run":
        return cmd_run(connector)
    if args.command == "status":
        return cmd_status(connector)
    if args.command == "validate-mcp":
        return cmd_validate_mcp(connector)
    if args.command == "reset":
        return cmd_reset(connector)
    if args.command == "service":
        return cmd_service(args, connector)

    raise SystemExit(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
