#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_dir="$project_dir/dist/N Agent Bridge.app"
release_kind=${AIR75_RELEASE_KIND:-development}
executable_path="$app_dir/Contents/MacOS/Air75AgentBridge"
profile_resource="$app_dir/Contents/Resources/Air75AgentBridge_Air75AgentBridgeCore.bundle/Air75V3.json"

if [[ "$release_kind" == "distribution" ]]; then
  dmg_path="$project_dir/dist/NAgentBridge.dmg"
elif [[ "$release_kind" == "development" ]]; then
  version_value=$(plutil -extract CFBundleShortVersionString raw "$app_dir/Contents/Info.plist")
  dmg_path="$project_dir/dist/NAgentBridge-$version_value-Development.dmg"
else
  echo "AIR75_RELEASE_KIND must be development or distribution." >&2
  exit 2
fi

[[ -x "$executable_path" ]]
[[ -f "$profile_resource" ]]
if strings "$executable_path" | rg -Fq "could not load resource bundle" \
   || strings "$executable_path" | rg -Fq "$project_dir/.build"; then
  echo "Release executable still contains a SwiftPM build-path resource fallback." >&2
  exit 1
fi
plutil -lint "$app_dir/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_dir"

if [[ -f "$dmg_path" ]]; then
  hdiutil verify "$dmg_path"
  shasum -a 256 "$dmg_path"
fi

signature_details=$(codesign -dv --verbose=4 "$app_dir" 2>&1)
if [[ "$release_kind" == "distribution" ]]; then
  [[ -f "$dmg_path" ]] || {
    echo "Missing public DMG: $dmg_path" >&2
    exit 1
  }
  /usr/bin/lipo "$executable_path" -verify_arch arm64 x86_64
  if [[ "$signature_details" != *"Authority=Developer ID Application:"* ]]; then
    echo "Public release is not signed with Developer ID Application." >&2
    exit 1
  fi
  if [[ "$signature_details" == *"TeamIdentifier=not set"* ]]; then
    echo "Public release has no Apple TeamIdentifier." >&2
    exit 1
  fi
  codesign --verify --verbose=2 "$dmg_path"
  spctl --assess --type execute --verbose=4 "$app_dir"
  xcrun stapler validate "$dmg_path"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"
else
  echo "Local development signature detected; Developer ID Gatekeeper assessment skipped."
fi

echo "Release structure verified."
