#!/usr/bin/env bash
# Sign a release bundle using a required Developer ID Application SIGNING_IDENTITY.
set -euo pipefail

BUNDLE="${1:?Usage: bash Scripts/sign-bundle.sh bundle}"
IDENTITY="${SIGNING_IDENTITY:-}"

if [[ "$IDENTITY" != "Developer ID Application: "* ]]; then
  echo 'SIGNING_IDENTITY must be a full Developer ID Application certificate name.' >&2
  exit 1
fi

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
