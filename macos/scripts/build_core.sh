#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$NEXT_DIR/.." && pwd)"

mkdir -p "$NEXT_DIR/Frameworks"
cd "$ROOT_DIR"
CGO_CFLAGS="-mmacosx-version-min=26.0" CGO_LDFLAGS="-mmacosx-version-min=26.0" go build -buildmode=c-archive -o "$NEXT_DIR/Frameworks/libsnowdrop.a" core/bridge_darwin.go
