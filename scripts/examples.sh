#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

found=0
for manifest in Examples/*/Package.swift; do
  [[ -e "$manifest" ]] || continue
  found=1
  package_dir="$(dirname "$manifest")"
  echo "==> swift test $package_dir"
  (
    cd "$package_dir"
    swift test
    if [[ "$(basename "$package_dir")" == "ProjectBrowser" ]]; then
      swift run ProjectBrowser
    fi
  )
done

if [[ "$found" -eq 0 ]]; then
  echo "error: no example packages found under Examples/" >&2
  exit 1
fi
