#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
output_dir="$project_dir/dist"
app_dir="$output_dir/N Agent Bridge.app"
release_kind=${AIR75_RELEASE_KIND:-development}
identity_value=${AIR75_SIGNING_IDENTITY:-}

if [[ "$release_kind" == "distribution" ]]; then
  dmg_path="$output_dir/NAgentBridge.dmg"
  if [[ "$identity_value" != "Developer ID Application:"* ]]; then
    echo "Public DMGs require AIR75_SIGNING_IDENTITY with a Developer ID Application identity." >&2
    exit 2
  fi
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity_value\""; then
    echo "Developer ID Application identity is not installed: $identity_value" >&2
    exit 2
  fi
elif [[ "$release_kind" != "development" ]]; then
  echo "AIR75_RELEASE_KIND must be development or distribution." >&2
  exit 2
else
  dmg_path=""
fi

if [[ ! -d "$app_dir" ]]; then
  AIR75_RELEASE_KIND="$release_kind" "$script_dir/build-release.sh"
fi
if [[ "$release_kind" == "development" ]]; then
  version_value=$(plutil -extract CFBundleShortVersionString raw "$app_dir/Contents/Info.plist")
  dmg_path="$output_dir/NAgentBridge-$version_value-Development.dmg"
fi
if [[ "$release_kind" == "distribution" ]]; then
  executable_path="$app_dir/Contents/MacOS/Air75AgentBridge"
  /usr/bin/lipo "$executable_path" -verify_arch arm64 x86_64
  signature_details=$(codesign -dv --verbose=4 "$app_dir" 2>&1)
  if [[ "$signature_details" != *"Authority=Developer ID Application:"* ]]; then
    echo "Refusing to package an app that is not signed with Developer ID Application." >&2
    exit 2
  fi
  codesign --verify --deep --strict --verbose=2 "$app_dir"
fi

staging_dir=$(mktemp -d /tmp/n-agent-bridge-dmg.XXXXXX)
cleanup() { /bin/rm -rf "$staging_dir"; }
trap cleanup EXIT
cp -R "$app_dir" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

if [[ "$dmg_path" != "$project_dir/dist/NAgentBridge.dmg" \
   && "$dmg_path" != "$project_dir/dist/NAgentBridge-$version_value-Development.dmg" ]]; then
  echo "Refusing unexpected DMG path: $dmg_path" >&2
  exit 1
fi
/bin/rm -f "$dmg_path" "$dmg_path.sha256"
hdiutil create -volname "N Agent Bridge" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"
if [[ "$release_kind" == "distribution" ]]; then
  codesign --force --timestamp --sign "$identity_value" "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"
fi
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Created: $dmg_path"
