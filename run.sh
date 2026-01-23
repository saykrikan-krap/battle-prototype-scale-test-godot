#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GODOT_ROOT="$SCRIPT_DIR/tools/godot/4.5.1"
UNAME="$(uname -s)"

case "$UNAME" in
  Linux*)
    GODOT_BIN="$GODOT_ROOT/linux/Godot_v4.5.1-stable_linux.x86_64"
    ;;
  Darwin*)
    GODOT_BIN="$GODOT_ROOT/macos/Godot.app/Contents/MacOS/Godot"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    GODOT_BIN="$GODOT_ROOT/windows/Godot_v4.5.1-stable_win64_console.exe"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

if [[ ! -f "$GODOT_BIN" ]]; then
  echo "Godot binary not found: $GODOT_BIN" >&2
  echo "Place the 4.5.1 binaries under tools/godot/4.5.1/." >&2
  exit 1
fi

if [[ "$UNAME" != MINGW* && "$UNAME" != MSYS* && "$UNAME" != CYGWIN* ]]; then
  if [[ ! -x "$GODOT_BIN" ]]; then
    chmod +x "$GODOT_BIN"
  fi
fi

resolve_only=0
headless=0
for arg in "$@"; do
  if [[ "$arg" == "--resolve-only" ]]; then
    resolve_only=1
  elif [[ "$arg" == "--headless" ]]; then
    headless=1
  fi
done

extra_args=()
if [[ $resolve_only -eq 1 && $headless -eq 0 ]]; then
  extra_args+=(--headless)
fi

exec "$GODOT_BIN" --path "$SCRIPT_DIR" "${extra_args[@]}" "$@"
