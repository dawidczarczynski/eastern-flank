#!/usr/bin/env bash
# PostToolUse: after a .gd file is edited, format it with gdformat.
# gdformat parses the file, so it also catches syntax errors – in that case exit 2 returns the error to the agent.
file=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))')
[[ "$file" == *.gd ]] || exit 0
command -v gdformat >/dev/null 2>&1 || exit 0

if ! out=$(gdformat "$file" 2>&1); then
	echo "gdformat failed to process $file – probably a syntax error:" >&2
	echo "$out" >&2
	exit 2
fi
exit 0
