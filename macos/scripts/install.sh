#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d build/TabLink.app ]] || ./scripts/build-all.sh
TARGET="$HOME/Applications/TabLink.app"
mkdir -p "$HOME/Applications"
ditto build/TabLink.app "$TARGET"
codesign --verify --deep --strict "$TARGET"
open "$TARGET"
echo "Installed $TARGET"
