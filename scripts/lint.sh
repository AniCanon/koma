#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "error: swiftformat is not installed. Install it with: brew install swiftformat" >&2
  exit 127
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint is not installed. Install it with: brew install swiftlint" >&2
  exit 127
fi

swiftformat --lint .
swiftlint lint --strict
