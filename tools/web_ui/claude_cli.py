"""Shared helpers of the dev web tools that run the Claude Code CLI headless (`claude -p`, stream-json).

Python 3.8, stdlib only. Used by the unit catalog jobs (tools/unit_catalog/jobs.py) and the devtools chat
(tools/devtools/chat.py).
"""
from __future__ import annotations

import glob
import json
import os
import re
import shutil
from typing import Any, Dict, List, Optional

SESSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,63}$")  # no leading dash: it follows --resume in argv
# the CLI's long permission refusals: a permission rule / dontAsk mode, and the auto mode classifier
DENIED_RE = re.compile(r"^Permission to use (\S+)(?: with command (.+?))? has been denied(.*)", re.S)
CLASSIFIER_RE = re.compile(r"^Permission for this action was denied by the Claude Code auto mode classifier\. Reason: \[?([^\]\n]+?)\]?\.")
VSCODE_GLOB = "~/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude"


def find_claude(env_var: str) -> Optional[str]:
    """Path of the `claude` CLI: $<env_var>, then PATH, then the binary bundled with the VS Code extension."""
    override = os.environ.get(env_var)
    if override:
        return override if os.access(override, os.X_OK) else None
    found = shutil.which("claude")
    if found:
        return found
    bundled = [p for p in glob.glob(os.path.expanduser(VSCODE_GLOB)) if os.access(p, os.X_OK)]
    return max(bundled, key=os.path.getmtime) if bundled else None


def agent_alive(pid: Any) -> bool:
    """Is a `claude` process with this pid still running (e.g. left behind when the tool was killed)?"""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            return b"claude" in f.read()
    except OSError:
        return False


def short(value: Any, limit: int = 160) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def tool_summary(name: str, args: Any) -> str:
    if not isinstance(args, dict):
        return name
    for key in ("file_path", "command", "pattern", "query", "url", "description", "skill", "path"):
        if isinstance(args.get(key), str):
            return "%s: %s" % (name, short(args[key], 140))
    return name


def _denial(text: str) -> Optional[str]:
    """A permission refusal in one short line, or None for any other tool error."""
    blocked = CLASSIFIER_RE.match(text)
    if blocked:
        return "blocked by the auto mode classifier: %s" % blocked.group(1)
    denied = DENIED_RE.match(text)
    if denied:
        what = denied.group(1) + (" " + denied.group(2) if denied.group(2) else "")
        return "denied: %s (%s)" % (what, "not on the allow-list" if "don't ask mode" in denied.group(3) else "deny rule")
    return None


def clip(value: Any, limit: int = 6000) -> Any:
    """Strings (also inside dicts and lists) cut to `limit` characters, newlines kept - for stored tool details."""
    if isinstance(value, str):
        return value if len(value) <= limit else value[:limit] + "\n… (%d more characters)" % (len(value) - limit)
    if isinstance(value, dict):
        return {k: clip(v, limit) for k, v in value.items()}
    if isinstance(value, list):
        return [clip(v, limit) for v in value[:200]]
    return value


def _result_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [b.get("text", "") if isinstance(b, dict) and b.get("type") == "text" else "[%s]" % (b.get("type") if isinstance(b, dict) else "?")
                 for b in content]  # fmt: skip
        return "\n".join(parts)
    return json.dumps(content, ensure_ascii=False)


def parse_stream_line(line: str, detail: bool = False) -> List[Dict[str, Any]]:
    """Turn one stream-json line into log entries `{"kind": text|tool|info|error|result, "text", ...}`, plus two
    kinds that are state, not log: `usage` (`context_tokens` of the main agent after one API call) and `limits`
    (the subscription's usage windows: `{"status", "windows": {"five_hour": {"utilization", "resets_at"}, ...}}`).

    With `detail` (the devtools chat): tool entries carry their `id` and (clipped) `input`, every tool result is a
    `tool_result` entry, CLI notices (slash command output, compaction, interrupts) become `info`, `system` turn
    starts are marked `turn_start`, and the control protocol comes through as `control` entries (`msg`)."""
    line = line.strip()
    if not line:
        return []
    try:
        msg = json.loads(line)
    except ValueError:
        return [{"kind": "info", "text": short(line, 400)}]
    if not isinstance(msg, dict):
        return []
    mtype = msg.get("type")
    sub = msg.get("parent_tool_use_id") is not None
    if mtype in ("control_request", "control_response"):
        return [{"kind": "control", "msg": msg}] if detail else []
    if mtype == "system" and msg.get("subtype") == "init":
        return [{"kind": "info", "text": "session %s started (%s)" % (msg.get("session_id", "?"), msg.get("model", "?")),
                 "session_id": msg.get("session_id"), "init": True}]  # fmt: skip
    if mtype == "system" and detail and msg.get("subtype") == "status" and msg.get("status") == "compacting":
        return [{"kind": "info", "text": "compacting the conversation…"}]
    if mtype == "rate_limit_event":
        info = msg.get("rate_limit_info") or {}
        windows = {}
        for name, window in (info.get("unifiedWindows") or {}).items():
            if isinstance(window, dict) and isinstance(window.get("utilization"), (int, float)):
                windows[str(name)] = {"utilization": window["utilization"], "resets_at": window.get("resetsAt")}
        return [{"kind": "limits", "status": str(info.get("status") or ""), "windows": windows}] if windows else []
    if mtype == "assistant":
        out = []
        usage = (msg.get("message") or {}).get("usage")
        if not sub and isinstance(usage, dict):
            tokens = sum(int(usage.get(k) or 0) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
            out.append({"kind": "usage", "context_tokens": tokens + int(usage.get("output_tokens") or 0)})
        for block in (msg.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text" and str(block.get("text", "")).strip():
                out.append({"kind": "text", "text": block["text"].strip(), "sub": sub})
            elif block.get("type") == "tool_use":
                entry = {"kind": "tool", "text": tool_summary(str(block.get("name")), block.get("input")), "sub": sub}
                if detail:
                    entry.update(id=block.get("id"), name=block.get("name"), input=clip(block.get("input")))
                out.append(entry)
        return out
    if mtype == "user":
        content = (msg.get("message") or {}).get("content")
        if isinstance(content, str):  # CLI notices: slash command output, the summary after a compaction
            if not detail:
                return []
            if "<local-command-stdout>" in content:
                text = content.replace("<local-command-stdout>", "").replace("</local-command-stdout>", "").strip()
                return [{"kind": "info", "text": text or "(command done)"}]
            if content.startswith("This session is being continued"):
                return [{"kind": "info", "text": "conversation compacted - earlier messages were summarized"}]
            return [{"kind": "info", "text": short(content, 300)}]
        out = []
        for block in content or []:
            if not isinstance(block, dict):
                continue
            if detail and block.get("type") == "text" and "[Request interrupted" in str(block.get("text")):
                out.append({"kind": "info", "text": "interrupted"})
            elif block.get("type") == "tool_result" and (detail or block.get("is_error")):
                text = _result_text(block.get("content"))
                if block.get("is_error"):
                    text = _denial(text) or text
                if detail:
                    out.append({"kind": "tool_result", "tool_use_id": block.get("tool_use_id"), "text": clip(text),
                                "is_error": bool(block.get("is_error")), "sub": sub})  # fmt: skip
                else:
                    out.append({"kind": "error", "text": short(text, 300), "sub": sub})
        return out
    if mtype == "result":
        windows = [m.get("contextWindow") for m in (msg.get("modelUsage") or {}).values() if isinstance(m, dict)]
        windows = [w for w in windows if isinstance(w, int)]
        return [{"kind": "result", "text": str(msg.get("result") or ""), "is_error": bool(msg.get("is_error")),
                 "cost_usd": msg.get("total_cost_usd"), "session_id": msg.get("session_id"),
                 "context_window": max(windows) if windows else None}]  # fmt: skip
    return []
