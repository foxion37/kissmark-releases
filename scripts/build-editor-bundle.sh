#!/usr/bin/env bash
# Rebuild the Milkdown Crepe editor bundle into Kissmark/Resources/Editor/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/_editor-build"
OUT="$ROOT/Kissmark/Resources/Editor"
cd "$BUILD"
npx esbuild entry.js \
  --bundle \
  --format=iife \
  --platform=browser \
  --target=safari15 \
  --outfile="$OUT/editor.bundle.js" \
  --loader:.css=css \
  --loader:.woff=empty \
  --loader:.woff2=empty \
  --loader:.ttf=empty \
  --loader:.eot=empty \
  --minify \
  --legal-comments=none
echo "Wrote $OUT/editor.bundle.js and editor.bundle.css"
