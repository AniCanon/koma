#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v docc >/dev/null 2>&1; then
  echo "error: docc is not available in PATH" >&2
  exit 127
fi

PORT="${1:-${DOCS_PORT:-8080}}"

swift package dump-symbol-graph --minimum-access-level public >/dev/null

SYMBOLGRAPH_DIR="$(find .build -type d -path '*/symbolgraph' | head -1)"
if [[ -z "${SYMBOLGRAPH_DIR:-}" ]]; then
  echo "error: SwiftPM did not produce a symbol graph directory" >&2
  exit 1
fi

rm -rf .build/docc-preview
mkdir -p .build/docc-preview

echo "Starting DocC API reference preview at http://localhost:${PORT}"
docc preview docs/Koma.docc \
  --port "$PORT" \
  --fallback-display-name Koma \
  --fallback-bundle-identifier org.anicanon.koma \
  --fallback-bundle-version 0.1.0 \
  --additional-symbol-graph-dir "$SYMBOLGRAPH_DIR" \
  --output-dir .build/docc-preview/Koma
