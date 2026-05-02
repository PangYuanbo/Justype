#!/bin/bash
# Resolve a stable code-signing identity for JustType.
# Preference order:
#   1. Apple Development / Apple Distribution (already in keychain — best)
#   2. Existing "JustType Local Sign" self-signed cert
#   3. Create a new self-signed cert and use it
#
# Stdout: the identity name to pass to `codesign --sign`
# Stderr: progress messages
set -euo pipefail

LOCAL_ID="JustType Local Sign"

# 1. Prefer an Apple-issued cert (most stable).
APPLE_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E "Apple (Development|Distribution)" \
    | head -1 \
    | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [ -n "$APPLE_ID" ]; then
    echo "→ Using Apple-issued cert: $APPLE_ID" >&2
    echo "$APPLE_ID"
    exit 0
fi

# 2. Existing self-signed.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$LOCAL_ID\""; then
    echo "→ Using local self-signed cert: $LOCAL_ID" >&2
    echo "$LOCAL_ID"
    exit 0
fi

# 3. Create one.
"$(dirname "$0")/ensure-cert.sh" "$LOCAL_ID" >&2
echo "$LOCAL_ID"
