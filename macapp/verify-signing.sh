#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: verify-signing.sh path/to/App.app}"
echo "=== codesign -dv ==="
codesign -dv --verbose=2 "$APP" 2>&1 || true
echo "=== codesign --verify ==="
codesign --verify --deep --strict --verbose=2 "$APP"
echo "=== spctl --assess (ad-hoc often rejects; OK for local) ==="
spctl --assess --type execute --verbose=4 "$APP" 2>&1 || echo "(expected reject for ad-hoc signing)"
