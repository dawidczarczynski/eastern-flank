#!/usr/bin/env bash
# Devtools hub: one page for every dev tool – starts the web tools (backlog viewer, unit catalog) and runs
# the command-line tools (check, tests, simulation, screenshots, unit render, game) from the browser.
# Usage: tools/devtools.sh [--port=8760]
set -euo pipefail
cd "$(dirname "$0")/.."

port=8760
for arg in "$@"; do
	case "$arg" in
	--port=*) port="${arg#--port=}" ;;
	*) echo "Unknown option: $arg (usage: tools/devtools.sh [--port=8760])" >&2; exit 2 ;;
	esac
done

url="http://localhost:${port}"
(
	# open the browser only once the hub answers
	for _ in $(seq 1 80); do
		if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${port}/api/commands', timeout=1)" >/dev/null 2>&1; then
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
exec python3 tools/devtools/server.py --port="$port"
