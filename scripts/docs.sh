#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v docc >/dev/null 2>&1; then
  echo "error: docc is not available in PATH" >&2
  exit 127
fi

swift package dump-symbol-graph --minimum-access-level public >/dev/null

SYMBOLGRAPH_DIR="$(find .build -type d -path '*/symbolgraph' | head -1)"
if [[ -z "${SYMBOLGRAPH_DIR:-}" ]]; then
  echo "error: SwiftPM did not produce a symbol graph directory" >&2
  exit 1
fi

rm -rf .build/docc-check
mkdir -p .build/docc-check

docc convert docs/Koma.docc \
  --fallback-display-name Koma \
  --fallback-bundle-identifier org.anicanon.koma \
  --fallback-bundle-version 0.2.0 \
  --additional-symbol-graph-dir "$SYMBOLGRAPH_DIR" \
  --output-dir .build/docc-check/Koma
