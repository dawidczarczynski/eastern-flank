# Sourced by the tools that can use the Windows build of Godot from WSL (GPU rendering – under
# WSLg with an old Mesa the Linux build falls back to software rendering).
# GODOT_WIN (WSL path, e.g. /mnt/c/Godot/Godot_v4.5.1-stable_win64.exe) overrides the search.
GODOT_WIN_VERSION="4.5.1"
GODOT_WIN_EXE="Godot_v${GODOT_WIN_VERSION}-stable_win64.exe"

# True when running inside WSL.
is_wsl() {
	grep -qi microsoft /proc/version 2>/dev/null
}

# Prints the WSL path of the Windows Godot exe (GODOT_WIN or the usual places on C:), or fails.
find_windows_godot() {
	if [[ -n "${GODOT_WIN:-}" ]]; then
		[[ -f "$GODOT_WIN" ]] && echo "$GODOT_WIN"
		return
	fi
	local candidate
	for candidate in \
		/mnt/c/Godot/"$GODOT_WIN_EXE" \
		/mnt/c/Godot/*/"$GODOT_WIN_EXE" \
		"/mnt/c/Program Files/Godot/$GODOT_WIN_EXE" \
		/mnt/c/Users/*/Downloads/"$GODOT_WIN_EXE" \
		/mnt/c/Users/*/Downloads/*/"$GODOT_WIN_EXE" \
		/mnt/c/Users/*/Desktop/"$GODOT_WIN_EXE" \
		/mnt/c/Users/*/Desktop/*/"$GODOT_WIN_EXE"; do
		# The zip extracts to a folder with the same name as the exe – skip that folder.
		if [[ -f "$candidate" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

# The console build next to the exe (its stdout/stderr reach the WSL pipe), or fails.
windows_console_godot() {
	local console="${1%.exe}_console.exe"
	[[ -f "$console" ]] && echo "$console"
}

windows_godot_missing_help() {
	echo "Could not find $GODOT_WIN_EXE. Download Godot $GODOT_WIN_VERSION for Windows (standard, not .NET) from" >&2
	echo "https://godotengine.org/download/archive/${GODOT_WIN_VERSION}-stable/ and unzip it to C:\\Godot," >&2
	echo "or set GODOT_WIN=/mnt/c/path/to/$GODOT_WIN_EXE" >&2
}

# Picks the Godot build for a render tool. $1 = "windows", "linux" or "" (auto: Windows under WSL
# when found). Prints the WSL path of the Windows console build, or nothing for the Linux build;
# fails (127, with help) when "windows" was asked for and the console build is missing.
pick_windows_godot() {
	local exe=""
	if [[ "$1" != "linux" ]] && is_wsl; then
		exe="$(find_windows_godot || true)"
		[[ -n "$exe" ]] && exe="$(windows_console_godot "$exe" || true)"
	fi
	if [[ "$1" == "windows" && -z "$exe" ]]; then
		windows_godot_missing_help
		echo "(the console build ${GODOT_WIN_EXE%.exe}_console.exe from the same zip is needed next to it)" >&2
		return 127
	fi
	echo "$exe"
}

# Runs a Godot script with the Windows console build:
#   run_windows_godot <console exe> <timeout s> <stdout file> <stderr file> <project dir> <godot args...>
# Windows sees the project through \\wsl.localhost\... and must start in a directory on C:. Absolute
# WSL paths in the arguments must already be Windows paths (wslpath -w). Environment variables named
# in GODOT_WIN_ENV (space separated) are passed through WSLENV. Output files get LF line endings.
# Returns Godot's exit code (124 on timeout – the Windows process is killed then, since killing the
# WSL side doesn't stop it; only scripts use the console build, so the editor/game are not affected).
run_windows_godot() {
	local exe="$1" limit="$2" out="$3" err="$4" project="$5"
	shift 5
	local wslenv="${WSLENV:-}" name
	for name in ${GODOT_WIN_ENV:-}; do
		wslenv="${wslenv:+$wslenv:}$name"
	done
	(cd /mnt/c && WSLENV="$wslenv" timeout "$limit" "$exe" --path "$(wslpath -w "$project")" "$@" \
		>"$out" 2>"$err" </dev/null)
	local status=$?
	if [[ $status -eq 124 ]]; then
		taskkill.exe /F /IM "$(basename "$exe")" >/dev/null 2>&1
	fi
	sed -i 's/\r$//' "$out" "$err"
	return $status
}

# Prints a Godot stdout file, turning the Windows path after "<prefix>" (e.g. "Render saved: ")
# back into a WSL path, so callers can open the reported file.
print_with_wsl_paths() {
	local file="$1" prefix="$2" line
	while IFS= read -r line; do
		if [[ "$line" == "$prefix"* ]]; then
			line="$prefix$(wslpath -u "${line#"$prefix"}")"
		fi
		printf '%s\n' "$line"
	done <"$file"
}
