#!/usr/bin/env bash
# Backlog viewer: docs/tasks/BACKLOG.md as a sortable, filterable page that follows file changes live.
# Usage: tools/backlog_view.sh [--port=8766]
set -euo pipefail
cd "$(dirname "$0")/.."

port=8766
for arg in "$@"; do
	case "$arg" in
	--port=*) port="${arg#--port=}" ;;
	*) echo "Unknown option: $arg (usage: tools/backlog_view.sh [--port=8766])" >&2; exit 2 ;;
	esac
done

url="http://localhost:${port}"
(
	# open the browser only once the server answers
	for _ in $(seq 1 40); do
		if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${port}/api/version', timeout=1)" >/dev/null 2>&1; then
			if command -v wslview >/dev/null 2>&1; then
				wslview "$url" >/dev/null 2>&1 || true
			elif command -v explorer.exe >/dev/null 2>&1; then
				explorer.exe "$url" >/dev/null 2>&1 || true
			elif command -v xdg-open >/dev/null 2>&1; then
				xdg-open "$url" >/dev/null 2>&1 || true
			fi
			break
		fi
		sleep 0.25
	done
) &
exec python3 tools/backlog_view/server.py --port="$port"
