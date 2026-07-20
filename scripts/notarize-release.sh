#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
dmg_path="$project_dir/dist/NAgentBridge.dmg"
app_dir="$project_dir/dist/N Agent Bridge.app"
notary_profile=${AIR75_NOTARY_PROFILE:-}

if [[ -z "$notary_profile" ]]; then
  echo "Set AIR75_NOTARY_PROFILE to a notarytool Keychain profile." >&2
  exit 2
fi
if [[ ! -f "$dmg_path" ]]; then
  echo "Missing public DMG: $dmg_path" >&2
  echo "Run scripts/release-public.sh so the notarized artifact cannot reuse a development build." >&2
  exit 2
fi

signature_details=$(codesign -dv --verbose=4 "$app_dir" 2>&1)
if [[ "$signature_details" != *"Authority=Developer ID Application:"* ]]; then
  echo "Refusing to notarize an app that is not signed with Developer ID Application." >&2
  exit 2
fi
/usr/bin/lipo "$app_dir/Contents/MacOS/Air75AgentBridge" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$app_dir"
codesign --verify --verbose=2 "$dmg_path"

xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Notarized and stapled: $dmg_path"
