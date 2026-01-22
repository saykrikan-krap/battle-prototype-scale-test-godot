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

exec "$GODOT_BIN" --path "$SCRIPT_DIR" "$@"
