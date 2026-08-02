#!/usr/bin/env python3
"""Discord bridge for Flea Market by Kafeena using plain-text audit events."""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

BASE = Path(__file__).resolve().parent
CONFIG_PATH = BASE / "config.json"
STATE_PATH = BASE / "bridge_state.json"
DEFAULT_AUDIT = Path.home() / "Zomboid" / "Lua" / "KafeenaFleaMarket_Audit.log"
LEGACY_QUEUE_NAMES = {"KafeenaFleaMarket_DiscordQueue.jsonl", "KafeenaFleaMarket_DiscordQueue.txt"}
AUDIT_RE = re.compile(r"^(.*?)\s*\|\s*([A-Z0-9_]+)\s*\|\s*(.*?)\s*\|\s*(.*)$")
COLORS = {
    "listed": 0xB45A45,
    "sold": 0x4E9A68,
    "promoted": 0xD4A72C,
    "cancelled": 0x777777,
    "expired": 0xA67C3B,
    "admin_removed": 0x9B3A3A,
    "test": 0x4E9A68,
}


def expand_path(value: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in {path}: {exc}") from exc


def save_state(offset: int) -> None:
    STATE_PATH.write_text(json.dumps({"offset": offset}, indent=2), encoding="utf-8")


def post_webhook(url: str, payload: dict[str, Any]) -> None:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url + "?wait=true",
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "KafeenaFleaMarket/1.1.5"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        if response.status not in (200, 204):
            raise RuntimeError(f"Discord returned HTTP {response.status}")


def parse_audit_event(line: str) -> dict[str, Any] | None:
    match = AUDIT_RE.match(line.strip())
    if not match:
        return None
    timestamp, audit_name, actor, details = match.groups()
    if not audit_name.startswith("DISCORD_"):
        return None
    event_name = audit_name[8:].lower()
    values = dict(urllib.parse.parse_qsl(details, keep_blank_values=True))
    return {
        "event": event_name,
        "listingId": values.get("listingId", ""),
        "item": values.get("item", ""),
        "fullType": values.get("fullType", ""),
        "price": int(values.get("price", "0") or 0),
        "condition": int(values.get("condition", "-1") or -1),
        "seller": values.get("seller", actor),
        "buyer": values.get("buyer", ""),
        "moderator": values.get("moderator", ""),
        "note": values.get("note", ""),
        "hours": int(values.get("hours", "0") or 0),
        "timestamp": values.get("timestamp", timestamp),
    }


def event_payload(event: dict[str, Any], config: dict[str, Any]) -> dict[str, Any]:
    event_name = str(event.get("event", "market")).lower()
    title_map = {
        "listed": "New Flea Market Listing",
        "sold": "Flea Market Item Sold",
        "promoted": "What's Hot Promotion",
        "cancelled": "Flea Market Listing Cancelled",
        "expired": "Flea Market Listing Expired",
        "admin_removed": "Flea Market Listing Removed by Admin",
        "test": "Flea Market Bridge Test",
    }
    fields: list[dict[str, Any]] = []
    if event.get("item"):
        fields.append({"name": "Item", "value": str(event["item"])[:1024], "inline": True})
    fields.append({"name": "Price", "value": f"${int(event.get('price', 0)):,}", "inline": True})
    if int(event.get("condition", -1)) >= 0:
        fields.append({"name": "Condition", "value": f"{int(event['condition'])}%", "inline": True})
    fields.extend([
        {"name": "Seller", "value": str(event.get("seller", "Unknown"))[:1024], "inline": True},
        {"name": "Listing", "value": str(event.get("listingId", "Unknown"))[:1024], "inline": True},
    ])
    if int(event.get("hours", 0)) > 0:
        fields.append({"name": "Duration", "value": f"{int(event['hours'])} in-game hours", "inline": True})
    if event.get("buyer"):
        fields.append({"name": "Buyer", "value": str(event["buyer"])[:1024], "inline": True})
    if event.get("moderator"):
        fields.append({"name": "Moderator", "value": str(event["moderator"])[:1024], "inline": True})
    if event.get("note"):
        fields.append({"name": "Seller Note", "value": str(event["note"])[:1024], "inline": False})
    role_id = str(config.get("mention_role_id", "")).strip()
    mention_event = event_name in {"listed", "promoted"}
    content = f"<@&{role_id}>" if role_id and mention_event else ""
    return {
        "content": content,
        "allowed_mentions": {"roles": [role_id], "parse": []} if role_id else {"parse": []},
        "embeds": [{
            "title": title_map.get(event_name, "Flea Market Event"),
            "color": COLORS.get(event_name, 0xB45A45),
            "fields": fields,
            "footer": {"text": f"{config.get('server_name', 'Project Zomboid')} • Flea Market by Kafeena"},
            "timestamp": event.get("timestamp"),
        }],
    }


def main() -> int:
    if not CONFIG_PATH.exists():
        print("Missing config.json. Copy config.example.json to config.json and add your webhook.")
        return 2
    config = load_json(CONFIG_PATH, {})
    webhook = str(config.get("webhook_url", ""))
    if "PASTE_YOURS_HERE" in webhook or not webhook.startswith("https://"):
        print("Set a valid webhook_url in config.json.")
        return 2
    audit_path = expand_path(str(config.get("queue_file", "")))
    if audit_path.name in LEGACY_QUEUE_NAMES or not str(config.get("queue_file", "")):
        audit_path = DEFAULT_AUDIT.resolve()
    poll_seconds = max(1.0, float(config.get("poll_seconds", 2)))
    enabled_events = set(config.get("send_events", ["listed", "sold", "promoted", "cancelled", "expired", "admin_removed"]))
    state = load_json(STATE_PATH, {"offset": 0})
    offset = max(0, int(state.get("offset", 0)))
    print(f"Watching plain-text audit log: {audit_path}")

    while True:
        try:
            if not audit_path.exists():
                time.sleep(poll_seconds)
                continue
            size = audit_path.stat().st_size
            if offset > size:
                offset = 0
            with audit_path.open("r", encoding="utf-8-sig", errors="replace") as handle:
                handle.seek(offset)
                while True:
                    line = handle.readline()
                    if not line:
                        break
                    event = parse_audit_event(line)
                    if event and (event["event"] == "test" or event["event"] in enabled_events):
                        post_webhook(webhook, event_payload(event, config))
                        print(f"Sent {event['event']} {event['listingId']}")
                    offset = handle.tell()
                    save_state(offset)
        except (OSError, RuntimeError, ValueError, urllib.error.URLError) as exc:
            print(f"Bridge error: {exc}", file=sys.stderr)
        time.sleep(poll_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
