#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export BENCHMARK_DISABLE_JEMALLOC="${BENCHMARK_DISABLE_JEMALLOC:-true}"
export KOMA_ENABLE_BENCHMARKS=1

swift package benchmark --target KomaBenchmarks "$@"
