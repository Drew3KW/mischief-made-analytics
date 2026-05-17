from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = PROJECT_ROOT / ".env"
OUTPUT_DIR = PROJECT_ROOT / "local_data" / "etsy_api_spike"

BASE_URL = "https://api.etsy.com/v3"
OAUTH_CONNECT_URL = "https://www.etsy.com/oauth/connect"
OAUTH_TOKEN_URL = "https://api.etsy.com/v3/public/oauth/token"

DEFAULT_SCOPES = ["transactions_r", "shops_r", "listings_r"]


def load_local_env() -> None:
    if not ENV_PATH.exists():
        return

    for raw_line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        if key and key not in os.environ:
            os.environ[key] = value


def require_env(name: str) -> str:
    value = os.environ.get(name)

    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")

    return value


def write_json(filename: str, payload: Any) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / filename
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    return path


def read_json(filename: str) -> dict[str, Any]:
    path = OUTPUT_DIR / filename

    if not path.exists():
        raise FileNotFoundError(f"Missing expected file: {path}")

    return json.loads(path.read_text(encoding="utf-8"))


def request_json(
    method: str,
    url: str,
    headers: dict[str, str] | None = None,
    form_data: dict[str, str] | None = None,
) -> tuple[Any, dict[str, str]]:
    body = None

    if form_data is not None:
        body = urllib.parse.urlencode(form_data).encode("utf-8")

    request = urllib.request.Request(
        url=url,
        data=body,
        headers=headers or {},
        method=method,
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response_body = response.read().decode("utf-8")
            payload = json.loads(response_body) if response_body else {}
            return payload, dict(response.headers)

    except urllib.error.HTTPError as error:
        error_body = error.read().decode("utf-8")
        raise RuntimeError(f"HTTP {error.code} {error.reason}: {error_body}") from error


def get_saved_access_token() -> str:
    env_token = os.environ.get("ETSY_ACCESS_TOKEN")

    if env_token:
        return env_token

    token_path = OUTPUT_DIR / "oauth_token.json"

    if token_path.exists():
        token_payload = json.loads(token_path.read_text(encoding="utf-8"))
        saved_token = token_payload.get("access_token")

        if saved_token:
            return saved_token

    raise RuntimeError(
        "Missing Etsy access token. Run auth-url and exchange-code first, "
        "or set ETSY_ACCESS_TOKEN in your local .env."
    )


def get_saved_refresh_token() -> str:
    env_token = os.environ.get("ETSY_REFRESH_TOKEN")

    if env_token:
        return env_token

    token_path = OUTPUT_DIR / "oauth_token.json"

    if token_path.exists():
        token_payload = json.loads(token_path.read_text(encoding="utf-8"))
        saved_token = token_payload.get("refresh_token")

        if saved_token:
            return saved_token

    raise RuntimeError(
        "Missing Etsy refresh token. Run exchange-code first, "
        "or set ETSY_REFRESH_TOKEN in your local .env."
    )


def etsy_headers(include_oauth: bool) -> dict[str, str]:
    keystring = require_env("ETSY_API_KEYSTRING")
    shared_secret = os.environ.get("ETSY_SHARED_SECRET", "")

    api_key_header = (
        f"{keystring}:{shared_secret}"
        if shared_secret
        else keystring
    )

    headers = {
        "Accept": "application/json",
        "x-api-key": api_key_header,
    }

    if include_oauth:
        headers["Authorization"] = f"Bearer {get_saved_access_token()}"

    return headers


def etsy_get(
    path: str,
    params: dict[str, Any] | None = None,
    include_oauth: bool = True,
) -> tuple[Any, dict[str, str]]:
    clean_params = {}

    for key, value in (params or {}).items():
        if value is not None:
            clean_params[key] = value

    query_string = urllib.parse.urlencode(clean_params, doseq=True)
    url = f"{BASE_URL}{path}"

    if query_string:
        url = f"{url}?{query_string}"

    return request_json("GET", url, headers=etsy_headers(include_oauth))


def money_to_float(value: dict[str, Any] | None) -> float | None:
    if not value:
        return None

    amount = value.get("amount")
    divisor = value.get("divisor")

    if amount is None or not divisor:
        return None

    return amount / divisor


def collect_paths(value: Any, prefix: str = "") -> set[str]:
    paths: set[str] = set()

    if isinstance(value, dict):
        if not value:
            paths.add(prefix or "<root>")
            return paths

        for key, nested_value in value.items():
            next_prefix = f"{prefix}.{key}" if prefix else key
            paths.add(next_prefix)
            paths.update(collect_paths(nested_value, next_prefix))

    elif isinstance(value, list):
        list_prefix = f"{prefix}[]" if prefix else "[]"
        paths.add(list_prefix)

        for item in value:
            paths.update(collect_paths(item, list_prefix))

    else:
        paths.add(prefix or "<root>")

    return paths


def write_field_inventory() -> None:
    sections = [
        "# Etsy API Spike Field Inventory",
        "",
        "Generated from local Etsy API spike JSON output.",
        "",
        "This file is local scratch output and should not be committed.",
        "",
    ]

    excluded_files = {"oauth_state.json", "oauth_token.json"}

    for path in sorted(OUTPUT_DIR.glob("*.json")):
        if path.name in excluded_files:
            continue

        payload = json.loads(path.read_text(encoding="utf-8"))
        paths = sorted(collect_paths(payload))

        sections.extend(
            [
                f"## {path.name}",
                "",
                f"Total field paths: {len(paths)}",
                "",
                "```text",
                *paths,
                "```",
                "",
            ]
        )

    inventory_path = OUTPUT_DIR / "field_inventory.md"
    inventory_path.write_text("\n".join(sections), encoding="utf-8")


def print_payload_summary(filename: str, payload: Any) -> None:
    path = write_json(filename, payload)
    print(f"Wrote {path}")

    if isinstance(payload, dict):
        count = payload.get("count")
        results = payload.get("results")

        if count is not None:
            print(f"API count: {count}")

        if isinstance(results, list):
            print(f"Returned results: {len(results)}")

            if results:
                first_keys = sorted(results[0].keys())
                print("First result keys:")
                for key in first_keys:
                    print(f"  {key}")


def unix_range_for_days(days: int) -> tuple[int, int]:
    max_created = int(time.time())
    min_created = max_created - (days * 24 * 60 * 60)
    return min_created, max_created


def make_pkce_pair() -> tuple[str, str]:
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("utf-8")
    verifier = verifier.rstrip("=")

    digest = hashlib.sha256(verifier.encode("utf-8")).digest()
    challenge = base64.urlsafe_b64encode(digest).decode("utf-8")
    challenge = challenge.rstrip("=")

    return verifier, challenge

def cmd_me(_: argparse.Namespace) -> None:
    payload, _ = etsy_get(
        "/application/users/me",
        include_oauth=True,
    )

    print_payload_summary("me.json", payload)
    write_field_inventory()

    shop_id = payload.get("shop_id")

    if shop_id:
        print("")
        print(f"ETSY_SHOP_ID={shop_id}")

def cmd_ping(_: argparse.Namespace) -> None:
    payload, _ = etsy_get("/application/openapi-ping", include_oauth=False)
    print_payload_summary("ping.json", payload)
    write_field_inventory()


def cmd_auth_url(args: argparse.Namespace) -> None:
    keystring = require_env("ETSY_API_KEYSTRING")
    redirect_uri = require_env("ETSY_REDIRECT_URI")

    scopes = args.scopes or DEFAULT_SCOPES
    state = secrets.token_urlsafe(32)
    verifier, challenge = make_pkce_pair()

    state_payload = {
        "state": state,
        "code_verifier": verifier,
        "code_challenge": challenge,
        "redirect_uri": redirect_uri,
        "scopes": scopes,
        "created_unix": int(time.time()),
    }

    write_json("oauth_state.json", state_payload)

    params = {
        "response_type": "code",
        "client_id": keystring,
        "redirect_uri": redirect_uri,
        "scope": " ".join(scopes),
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }

    url = f"{OAUTH_CONNECT_URL}?{urllib.parse.urlencode(params)}"

    print("Open this URL in your browser:")
    print(url)
    print("")
    print("Saved OAuth state and PKCE verifier to:")
    print(OUTPUT_DIR / "oauth_state.json")


def cmd_exchange_code(args: argparse.Namespace) -> None:
    state_payload = read_json("oauth_state.json")

    form_data = {
        "grant_type": "authorization_code",
        "client_id": require_env("ETSY_API_KEYSTRING"),
        "redirect_uri": state_payload["redirect_uri"],
        "code": args.code.strip(),
        "code_verifier": state_payload["code_verifier"],
    }

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    }

    payload, _ = request_json(
        "POST",
        OAUTH_TOKEN_URL,
        headers=headers,
        form_data=form_data,
    )

    path = write_json("oauth_token.json", payload)

    print(f"Wrote OAuth token response to {path}")
    print(f"Token type: {payload.get('token_type')}")
    print(f"Expires in seconds: {payload.get('expires_in')}")
    print(f"Refresh token present: {'refresh_token' in payload}")


def cmd_refresh_token(_: argparse.Namespace) -> None:
    form_data = {
        "grant_type": "refresh_token",
        "client_id": require_env("ETSY_API_KEYSTRING"),
        "refresh_token": get_saved_refresh_token(),
    }

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    }

    payload, _ = request_json(
        "POST",
        OAUTH_TOKEN_URL,
        headers=headers,
        form_data=form_data,
    )

    path = write_json("oauth_token.json", payload)

    print(f"Wrote refreshed OAuth token response to {path}")
    print(f"Token type: {payload.get('token_type')}")
    print(f"Expires in seconds: {payload.get('expires_in')}")
    print(f"Refresh token present: {'refresh_token' in payload}")


def cmd_receipts(args: argparse.Namespace) -> None:
    shop_id = require_env("ETSY_SHOP_ID")
    min_created, max_created = unix_range_for_days(args.days)

    params = {
        "min_created": min_created,
        "max_created": max_created,
        "limit": args.limit,
        "offset": args.offset,
        "sort_on": "created",
        "sort_order": "desc",
    }

    payload, _ = etsy_get(
        f"/application/shops/{shop_id}/receipts",
        params=params,
        include_oauth=True,
    )

    print_payload_summary("receipts_sample.json", payload)
    write_field_inventory()


def cmd_receipt_transactions(args: argparse.Namespace) -> None:
    shop_id = require_env("ETSY_SHOP_ID")

    payload, _ = etsy_get(
        f"/application/shops/{shop_id}/receipts/{args.receipt_id}/transactions",
        include_oauth=True,
    )

    print_payload_summary(
        f"receipt_{args.receipt_id}_transactions_sample.json",
        payload,
    )
    write_field_inventory()


def cmd_receipt_payment(args: argparse.Namespace) -> None:
    shop_id = require_env("ETSY_SHOP_ID")

    payload, _ = etsy_get(
        f"/application/shops/{shop_id}/receipts/{args.receipt_id}/payments",
        include_oauth=True,
    )

    print_payload_summary(
        f"receipt_{args.receipt_id}_payment_sample.json",
        payload,
    )
    write_field_inventory()


def cmd_ledger(args: argparse.Namespace) -> None:
    shop_id = require_env("ETSY_SHOP_ID")
    min_created, max_created = unix_range_for_days(args.days)

    params = {
        "min_created": min_created,
        "max_created": max_created,
        "limit": args.limit,
        "offset": args.offset,
    }

    payload, _ = etsy_get(
        f"/application/shops/{shop_id}/payment-account/ledger-entries",
        params=params,
        include_oauth=True,
    )

    print_payload_summary("ledger_entries_sample.json", payload)
    write_field_inventory()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Local Etsy Open API spike helper."
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    me_parser = subparsers.add_parser(
        "me",
        help="Fetch the authenticated Etsy user and shop ID.",
    )
    me_parser.set_defaults(func=cmd_me)

    ping_parser = subparsers.add_parser(
        "ping",
        help="Test Etsy API key connectivity.",
    )
    ping_parser.set_defaults(func=cmd_ping)

    auth_parser = subparsers.add_parser(
        "auth-url",
        help="Generate an Etsy OAuth authorization URL.",
    )
    auth_parser.add_argument(
        "--scopes",
        nargs="+",
        default=DEFAULT_SCOPES,
        help="OAuth scopes to request.",
    )
    auth_parser.set_defaults(func=cmd_auth_url)

    exchange_parser = subparsers.add_parser(
        "exchange-code",
        help="Exchange an Etsy OAuth code for tokens.",
    )
    exchange_parser.add_argument("code", help="Authorization code from Etsy.")
    exchange_parser.set_defaults(func=cmd_exchange_code)

    refresh_parser = subparsers.add_parser(
        "refresh-token",
        help="Refresh the saved Etsy OAuth token.",
    )
    refresh_parser.set_defaults(func=cmd_refresh_token)

    receipts_parser = subparsers.add_parser(
        "receipts",
        help="Fetch a recent sample of Etsy shop receipts.",
    )
    receipts_parser.add_argument("--days", type=int, default=30)
    receipts_parser.add_argument("--limit", type=int, default=25)
    receipts_parser.add_argument("--offset", type=int, default=0)
    receipts_parser.set_defaults(func=cmd_receipts)

    transaction_parser = subparsers.add_parser(
        "receipt-transactions",
        help="Fetch transactions for one Etsy receipt.",
    )
    transaction_parser.add_argument("receipt_id", type=int)
    transaction_parser.set_defaults(func=cmd_receipt_transactions)

    payment_parser = subparsers.add_parser(
        "receipt-payment",
        help="Fetch payment data for one Etsy receipt.",
    )
    payment_parser.add_argument("receipt_id", type=int)
    payment_parser.set_defaults(func=cmd_receipt_payment)

    ledger_parser = subparsers.add_parser(
        "ledger",
        help="Fetch recent Etsy payment account ledger entries.",
    )
    ledger_parser.add_argument("--days", type=int, default=30)
    ledger_parser.add_argument("--limit", type=int, default=25)
    ledger_parser.add_argument("--offset", type=int, default=0)
    ledger_parser.set_defaults(func=cmd_ledger)

    return parser


def main() -> None:
    load_local_env()

    parser = build_parser()
    args = parser.parse_args()

    try:
        args.func(args)
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()