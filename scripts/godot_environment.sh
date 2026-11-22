#!/usr/bin/env bash
# Source this file from the repository root.
# shellcheck source=scripts/godot.env
source "${GODOT_CONFIG:-scripts/godot.env}"
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) GODOT_PLATFORM=linux.x86_64; GODOT_SHA256=$GODOT_LINUX_X86_64_SHA256 ;;
  Linux/aarch64|Linux/arm64) GODOT_PLATFORM=linux.arm64; GODOT_SHA256=$GODOT_LINUX_ARM64_SHA256 ;;
  Darwin/*) GODOT_PLATFORM=macos.universal; GODOT_SHA256=$GODOT_MACOS_SHA256 ;;
  *) echo 'Supported installation platforms: Linux x86_64/arm64 and macOS.' >&2; return 1 ;;
esac
GODOT_FILE="Godot_v${GODOT_VERSION}-stable_${GODOT_PLATFORM}"
godot_dir_override="${GODOT_DIR:-${RUNNER_TEMP:-}}"
GODOT_DIR="${godot_dir_override:-$PWD/.cache/godot/$GODOT_VERSION/$GODOT_PLATFORM}"
godot_binary_rel="$GODOT_FILE"
if [ "$GODOT_PLATFORM" = macos.universal ]; then
  godot_binary_rel="Godot.app/Contents/MacOS/Godot"
fi
GODOT_BINARY="$GODOT_DIR/$godot_binary_rel"
if [ -z "$godot_dir_override" ] && { [ ! -f "$GODOT_BINARY" ] || [ ! -x "$GODOT_BINARY" ]; }; then
  godot_common_git_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ -z "$godot_common_git_dir" ]; then
    godot_common_git_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
    if [ -n "$godot_common_git_dir" ] && [ -d "$godot_common_git_dir" ]; then
      godot_common_git_dir=$(cd "$godot_common_git_dir" 2>/dev/null && pwd -P || true)
    fi
  fi
  if [ -n "$godot_common_git_dir" ]; then
    godot_common_dir="$(dirname "$godot_common_git_dir")/.cache/godot/$GODOT_VERSION/$GODOT_PLATFORM"
    if [ -f "$godot_common_dir/$godot_binary_rel" ] && [ -x "$godot_common_dir/$godot_binary_rel" ]; then
      GODOT_DIR="$godot_common_dir"
      GODOT_BINARY="$GODOT_DIR/$godot_binary_rel"
    fi
  fi
fi
unset godot_dir_override godot_binary_rel godot_common_git_dir godot_common_dir
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'version=%s\nsha256=%s\nbinary=%s\n' "$GODOT_VERSION" "$GODOT_SHA256" "$GODOT_BINARY" >> "$GITHUB_OUTPUT"
fi
