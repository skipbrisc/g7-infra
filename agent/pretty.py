#!/usr/bin/env python3
"""Readable view of Claude Code's stream-json output, for G7 agent jobs.

Installed as /usr/local/lib/g7-agent/pretty.py. Source: agent/pretty.py in g7-infra.

  claude -p ... --output-format stream-json --verbose | pretty.py      one line per event
  pretty.py --summary <log.jsonl> <job dir>                            writes result.txt and
      summary.json from the last "result" event, prints ok, error or none

The tmux pane and pretty.log show this view; log.jsonl keeps the raw stream.
"""
import json
import signal
import sys

WIDTH = 150


def short(value, width=WIDTH):
    text = " ".join(str(value).split())
    return text if len(text) <= width else text[: width - 3] + "..."


def tool_summary(inp):
    if not isinstance(inp, dict):
        return short(inp)
    for key in ("command", "file_path", "path", "pattern", "url", "description", "query", "prompt", "skill"):
        value = inp.get(key)
        if value:
            if key == "command":
                lines = str(value).splitlines()
                value = lines[0] + (" ..." if len(lines) > 1 else "") if lines else value
            return short(value)
    return short(json.dumps(inp, ensure_ascii=False))


def tool_result_text(block):
    content = block.get("content")
    if isinstance(content, list):
        content = "\n".join(
            part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text"
        )
    return str(content or "")


def money(value):
    return f"~${value:.2f}" if isinstance(value, (int, float)) else "cost ?"


def show(event, out):
    kind = event.get("type")
    prefix = "  [subagent] " if event.get("parent_tool_use_id") else ""
    if kind == "system":
        sub = event.get("subtype")
        if sub == "init":
            out(f"==> session {event.get('session_id', '?')}  model {event.get('model', '?')}  in {event.get('cwd', '?')}")
        elif sub == "api_retry":
            out(f"... API retry {event.get('attempt')}/{event.get('max_retries')} ({event.get('error')})")
        elif sub == "permission_denied":
            out(f"  !! denied: {short(event.get('tool_name') or event)}")
        return
    if kind == "assistant":
        for block in (event.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text" and str(block.get("text", "")).strip():
                for line in block["text"].rstrip().splitlines():
                    out(prefix + line)
            elif block.get("type") == "tool_use":
                out(f"{prefix}  * {block.get('name')}: {tool_summary(block.get('input'))}")
        return
    if kind == "user":
        content = (event.get("message") or {}).get("content")
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    lines = tool_result_text(block).strip().splitlines()
                    if lines:
                        mark = "!!" if block.get("is_error") else "->"
                        more = f"  (+{len(lines) - 1} lines)" if len(lines) > 1 else ""
                        out(f"{prefix}    {mark} {short(lines[0], 130)}{more}")
        return
    if kind == "result":
        secs = (event.get("duration_ms") or 0) / 1000
        out(f"==> {event.get('subtype')}  turns {event.get('num_turns')}  {money(event.get('total_cost_usd'))}  {secs / 60:.0f} min")
        if event.get("result"):
            out(str(event["result"]))


def stream():
    signal.signal(signal.SIGINT, signal.SIG_IGN)  # Ctrl-C is for Claude; keep the log flowing

    def out(line):
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    for raw in sys.stdin:
        raw = raw.rstrip("\n")
        if not raw.strip():
            continue
        try:
            event = json.loads(raw)
        except ValueError:
            out(raw)
            continue
        if isinstance(event, dict):
            try:
                show(event, out)
            except Exception as exc:  # never let one odd event stop the view
                out(f"(could not show an event: {exc})")


def summary(log_path, job_dir):
    last = None
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            if '"type":"result"' not in raw and '"type": "result"' not in raw:
                continue
            try:
                event = json.loads(raw)
            except ValueError:
                continue
            if isinstance(event, dict) and event.get("type") == "result":
                last = event
    if last is None:
        print("none")
        return
    keep = {k: last.get(k) for k in ("subtype", "is_error", "num_turns", "total_cost_usd", "duration_ms", "session_id")}
    keep["permission_denials"] = len(last.get("permission_denials") or [])
    with open(f"{job_dir}/summary.json", "w", encoding="utf-8") as handle:
        json.dump(keep, handle, indent=1)
    with open(f"{job_dir}/result.txt", "w", encoding="utf-8") as handle:
        handle.write(str(last.get("result") or "").rstrip() + "\n")
    print("error" if last.get("is_error") or last.get("subtype") != "success" else "ok")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 4 and sys.argv[1] == "--summary":
            summary(sys.argv[2], sys.argv[3])
        else:
            stream()
    except BrokenPipeError:
        pass
