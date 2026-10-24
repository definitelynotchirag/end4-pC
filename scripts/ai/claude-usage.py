#!/usr/bin/env python3
import glob
import json
import os
import time
import urllib.request
from datetime import datetime

home = os.path.expanduser("~/.claude")
now = time.time()
window = 5 * 3600

sessions = []
for path in glob.glob(os.path.join(home, "sessions", "*.json")):
    try:
        with open(path) as f:
            session = json.load(f)
    except Exception:
        continue
    if os.path.exists(f"/proc/{session.get('pid')}"):
        sessions.append({
            "name": session.get("name", ""),
            "status": session.get("status", ""),
            "cwd": session.get("cwd", ""),
        })

entries = {}
for path in glob.glob(os.path.join(home, "projects", "*", "*.jsonl")):
    if now - os.path.getmtime(path) > window * 2:
        continue
    with open(path, errors="ignore") as f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                data = json.loads(line)
                ts = datetime.fromisoformat(data["timestamp"].replace("Z", "+00:00")).timestamp()
                if now - ts > window * 2:
                    continue
                message = data["message"]
                usage = message["usage"]
                key = (message.get("id"), data.get("requestId"))
                entries[key] = (ts, usage.get("input_tokens", 0) + usage.get("output_tokens", 0) + usage.get("cache_creation_input_tokens", 0))
            except Exception:
                continue

tokens, start = 0, None
for ts, count in sorted(entries.values()):
    if start is None or ts >= start + window:
        start, tokens = ts - ts % 3600, 0
    tokens += count
if start is None or now >= start + window:
    tokens, start = 0, None



def to_epoch(value):
    if not value:
        return 0
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())


# Real limits from the endpoint Claude Code's /usage reads, using its own
# OAuth login. Falls back to the local token estimate above when unavailable.
limits = None
try:
    with open(os.path.join(home, ".credentials.json")) as f:
        oauth = json.load(f)["claudeAiOauth"]
    if oauth.get("expiresAt", 0) / 1000 > now:
        request = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
            "Authorization": f"Bearer {oauth['accessToken']}",
            "anthropic-beta": "oauth-2025-04-20",
        })
        with urllib.request.urlopen(request, timeout=8) as response:
            data = json.load(response)
        session, week = data.get("five_hour") or {}, data.get("seven_day") or {}
        limits = {
            "sessionPercent": session.get("utilization") or 0,
            "sessionResetsAt": to_epoch(session.get("resets_at")),
            "weekPercent": week.get("utilization") or 0,
            "weekResetsAt": to_epoch(week.get("resets_at")),
        }
except Exception:
    pass

print(json.dumps({
    "sessions": sessions,
    "tokens": tokens,
    "resetsAt": int(start + window) if start else 0,
    "live": limits is not None,
    **(limits or {}),
}))
