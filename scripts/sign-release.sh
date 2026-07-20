#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_dir="$project_dir/dist/N Agent Bridge.app"
identity_value=${AIR75_SIGNING_IDENTITY:-}

if [[ "$identity_value" != "Developer ID Application:"* ]]; then
  echo "Set AIR75_SIGNING_IDENTITY to a Developer ID Application identity." >&2
  exit 2
fi
if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity_value\""; then
  echo "Developer ID Application identity is not installed: $identity_value" >&2
  exit 2
fi
if [[ ! -d "$app_dir" ]]; then
  AIR75_RELEASE_KIND=distribution "$script_dir/build-release.sh"
fi

/usr/bin/lipo "$app_dir/Contents/MacOS/Air75AgentBridge" -verify_arch arm64 x86_64
codesign --force --options runtime --timestamp --sign "$identity_value" "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
echo "Signed: $app_dir"
