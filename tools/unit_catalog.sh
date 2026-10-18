#!/usr/bin/env bash
# Unit catalog: local web tool for collecting real-unit references (TASK-037). Usage: tools/unit_catalog.sh [--port=8765]
set -euo pipefail
cd "$(dirname "$0")/.."

port=8765
for arg in "$@"; do
	case "$arg" in
	--port=*) port="${arg#--port=}" ;;
	*) echo "Unknown option: $arg (usage: tools/unit_catalog.sh [--port=8765])" >&2; exit 2 ;;
	esac
done

url="http://localhost:${port}"
(
	# open the browser only once the server answers
	for _ in $(seq 1 40); do
		if python3 -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:${port}/api/catalog', timeout=1)" >/dev/null 2>&1; then
			if command -v wslview >/dev/null 2>&1; then
				wslview "$url" >/dev/null 2>&1 || true
			elif command -v explorer.exe >/dev/null 2>&1; then
				explorer.exe "$url" >/dev/null 2>&1 || true
			fi
			break
		fi
		sleep 0.25
	done
) &
exec python3 tools/unit_catalog/server.py --port="$port"
