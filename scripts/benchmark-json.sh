#!/usr/bin/env bash
set -euo pipefail

RESULT_DIR="${1:-.benchmark-results/koma-json-local}"
shift || true

mkdir -p "$RESULT_DIR"

export KOMA_ENABLE_BENCHMARKS=1
export BENCHMARK_DISABLE_JEMALLOC="${BENCHMARK_DISABLE_JEMALLOC:-true}"

swift run -c release KomaJSONBenchmarks "$@" | tee "$RESULT_DIR/results.txt"

cat > "$RESULT_DIR/metadata.json" <<JSON
{
  "suite": "KomaJSONBenchmarks",
  "date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "swift": "$(swift --version | head -n 1)"
}
JSON
