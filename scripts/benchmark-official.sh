#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export BENCHMARK_DISABLE_JEMALLOC="${BENCHMARK_DISABLE_JEMALLOC:-true}"
export KOMA_ENABLE_BENCHMARKS=1

RESULT_DIR="${1:-.benchmark-results/$(date -u +%Y%m%dT%H%M%SZ)}"
shift || true

mkdir -p "$RESULT_DIR"

SWIFT_VERSION="$(swift --version | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
GIT_REVISION="$(git rev-parse --verify HEAD 2>/dev/null || echo unknown)"
GIT_TAG="$(git describe --tags --exact-match 2>/dev/null || echo untagged)"
PLATFORM="$(uname -smr)"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMAND="swift package benchmark --target KomaBenchmarks $*"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

cat > "$RESULT_DIR/metadata.json" <<JSON
{
  "schemaVersion": 1,
  "suite": "KomaBenchmarks",
  "startedAt": "$(json_escape "$STARTED_AT")",
  "gitRevision": "$(json_escape "$GIT_REVISION")",
  "gitTag": "$(json_escape "$GIT_TAG")",
  "swiftVersion": "$(json_escape "$SWIFT_VERSION")",
  "platform": "$(json_escape "$PLATFORM")",
  "command": "$(json_escape "$COMMAND")"
}
JSON

swift package benchmark --target KomaBenchmarks "$@" | tee "$RESULT_DIR/results.txt"

FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RESULT_DIR/summary.md" <<MARKDOWN
# Koma Benchmark Run

- Suite: KomaBenchmarks
- Started: $STARTED_AT
- Finished: $FINISHED_AT
- Git revision: $GIT_REVISION
- Git tag: $GIT_TAG
- Swift: $SWIFT_VERSION
- Platform: $PLATFORM

See \`results.txt\` for raw benchmark output and \`metadata.json\` for machine-readable run metadata.
MARKDOWN

echo "Benchmark artifacts written to $RESULT_DIR"
