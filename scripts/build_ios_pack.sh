#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
NATIVE_LIB="$ROOT_DIR/ios/candarnetwork.xcframework/ios-arm64/libgodot.a"
DEST_PCK="$ROOT_DIR/ios/candarnetwork.pck"
TEMP_DIR="$(mktemp -d -t candarnetwork-ios)"
TEMP_PROJECT="$TEMP_DIR/project"
TEMP_PCK="$TEMP_DIR/candarnetwork.pck"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable not found: $GODOT_BIN" >&2
  exit 1
fi

if [[ ! -f "$NATIVE_LIB" ]]; then
  echo "Native iOS Godot library not found: $NATIVE_LIB" >&2
  exit 1
fi

godot_version="$("$GODOT_BIN" --version | head -n 1)"
native_version="$(LC_ALL=C strings "$NATIVE_LIB" | LC_ALL=C sed -nE 's/^Godot Engine v([0-9]+\.[0-9]+)\..*/\1/p' | head -n 1)"
pack_version="$(printf '%s\n' "$godot_version" | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')"

if [[ -z "$native_version" || -z "$pack_version" ]]; then
  echo "Could not determine Godot engine versions." >&2
  exit 1
fi

if [[ "$native_version" != "$pack_version" ]]; then
  echo "Godot version mismatch: pack exporter is $pack_version, iOS engine is $native_version." >&2
  echo "Use a Godot $native_version executable through GODOT_BIN." >&2
  exit 1
fi

echo "Exporting iOS pack with Godot $godot_version"
mkdir -p "$TEMP_PROJECT"
rsync -a "$ROOT_DIR/" "$TEMP_PROJECT/" \
  --exclude=".git/" \
  --exclude=".godot/" \
  --exclude="ios/" \
  --exclude="build/" \
  --exclude="test-artifacts/" \
  --exclude="marketing/" \
  --exclude="store-screenshots/" \
  --exclude="videos/" \
  --exclude="functions/" \
  --exclude="public/" \
  --exclude=".firebase/" \
  --exclude="*.aab" \
  --exclude="*.ipa" \
  --exclude="*.pck" \
  --exclude="*.bak" \
  --exclude="*.bak2"

echo "Importing project resources with Godot $pack_version"
"$GODOT_BIN" --headless --recovery-mode --single-threaded-scene --path "$TEMP_PROJECT" --import
"$GODOT_BIN" --headless --path "$TEMP_PROJECT" --export-pack "iOS" "$TEMP_PCK"

echo "Running pack smoke test"
"$GODOT_BIN" --headless --main-pack "$TEMP_PCK" --quit-after 2

cp "$TEMP_PCK" "$DEST_PCK"
echo "Created $DEST_PCK"
