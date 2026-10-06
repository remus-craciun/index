#!/bin/sh
# Builds the Flutter web client and copies it where the Go server embeds it.
# Run from anywhere. Coolify only compiles server/, so this has to happen
# before that build, and the resulting dist/ has to be part of what it compiles.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root/mobile"
flutter build web --release \
  --base-href / \
  --dart-define=INDEX_SAME_ORIGIN=true \
  --no-web-resources-cdn \
  --no-wasm-dry-run
dest="$root/server/internal/webui/dist"
rm -rf "$dest"
mkdir -p "$dest"
cp -a build/web/. "$dest/"
