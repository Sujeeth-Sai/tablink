#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
# Command Line Tools do not bundle XCTest. Run the identical tests through a zero-dependency assertion runner.
if swift -e 'import XCTest' >/dev/null 2>&1; then
  swift test --build-system native
else
  swiftc Sources/TabLinkCore/*.swift Tests/TabLinkCoreTests/CoreTests.swift scripts/test-runner/main.swift -o .build/checks/core-tests
  .build/checks/core-tests
fi
python3 scripts/check-vectors.py
