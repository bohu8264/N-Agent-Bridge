#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
distribution_dir="$project_dir/Distribution"
output_dir="$project_dir/dist"
app_dir="$output_dir/N Agent Bridge.app"
version_value=${AIR75_VERSION:-0.9.9}
build_value=${AIR75_BUILD_NUMBER:-24}
release_kind=${AIR75_RELEASE_KIND:-development}
identity_value=${AIR75_SIGNING_IDENTITY:-N Agent Bridge Local Signing}
arch_values=${AIR75_RELEASE_ARCHS:-}
swift_sandbox_flags=()
if [[ ${AIR75_DISABLE_SWIFTPM_SANDBOX:-0} == 1 ]]; then
  swift_sandbox_flags+=(--disable-sandbox)
fi

cd "$project_dir"
case "$release_kind" in
  development)
    [[ -n "$arch_values" ]] || arch_values=$(uname -m)
    ;;
  distribution)
    [[ -n ${AIR75_VERSION:-} ]] || {
      echo "Set AIR75_VERSION for a public release." >&2
      exit 2
    }
    [[ -n ${AIR75_BUILD_NUMBER:-} ]] || {
      echo "Set AIR75_BUILD_NUMBER for a public release." >&2
      exit 2
    }
    [[ -n "$arch_values" ]] || arch_values="arm64 x86_64"
    if [[ "$identity_value" != "Developer ID Application:"* ]]; then
      echo "Public releases require a Developer ID Application identity." >&2
      exit 2
    fi
    ;;
  *)
    echo "AIR75_RELEASE_KIND must be development or distribution." >&2
    exit 2
    ;;
esac

if [[ "$identity_value" != "-" ]] && ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity_value\""; then
  echo "Missing stable signing identity: $identity_value" >&2
  if [[ "$release_kind" == "development" ]]; then
    echo "Run ./scripts/ensure-local-signing-identity.sh once before building." >&2
  else
    echo "Install a Developer ID Application certificate from your Apple Developer account." >&2
  fi
  exit 2
fi

archs=(${=arch_values})
if (( ${#archs[@]} == 0 )); then
  echo "No release architectures selected." >&2
  exit 2
fi

binary_paths=()
release_bin_dirs=()
for arch_value in "${archs[@]}"; do
  case "$arch_value" in
    arm64|x86_64) ;;
    *)
      echo "Unsupported release architecture: $arch_value" >&2
      exit 2
      ;;
  esac
  scratch_path="$project_dir/.build/release-$arch_value"
  swift build "${swift_sandbox_flags[@]}" -c release --product Air75AgentBridge \
    --arch "$arch_value" --scratch-path "$scratch_path"
  release_bin_dir=$(swift build "${swift_sandbox_flags[@]}" -c release --show-bin-path \
    --arch "$arch_value" --scratch-path "$scratch_path")
  binary_path="$release_bin_dir/Air75AgentBridge"
  [[ -x "$binary_path" ]] || {
    echo "Missing release executable for $arch_value: $binary_path" >&2
    exit 1
  }
  binary_paths+=("$binary_path")
  release_bin_dirs+=("$release_bin_dir")
done

if [[ "$app_dir" != "$project_dir/dist/N Agent Bridge.app" ]]; then
  echo "Refusing unexpected app path: $app_dir" >&2
  exit 1
fi
/bin/rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
if (( ${#binary_paths[@]} == 1 )); then
  cp "${binary_paths[1]}" "$app_dir/Contents/MacOS/Air75AgentBridge"
else
  /usr/bin/lipo -create "${binary_paths[@]}" -output "$app_dir/Contents/MacOS/Air75AgentBridge"
fi
chmod 755 "$app_dir/Contents/MacOS/Air75AgentBridge"
cp "$distribution_dir/Info.plist" "$app_dir/Contents/Info.plist"
if [[ ! -f "$distribution_dir/AppIcon.icns" ]]; then
  echo "Missing application icon: $distribution_dir/AppIcon.icns" >&2
  exit 1
fi
cp "$distribution_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$version_value" "$app_dir/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_value" "$app_dir/Contents/Info.plist"

for resource_bundle in "${release_bin_dirs[1]}"/*.bundle; do
  [[ -e "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$app_dir/Contents/Resources/"
done

profile_resource="$app_dir/Contents/Resources/Air75AgentBridge_Air75AgentBridgeCore.bundle/Air75V3.json"
[[ -f "$profile_resource" ]] || {
  echo "Missing packaged device profile: $profile_resource" >&2
  exit 1
}

for arch_value in "${archs[@]}"; do
  /usr/bin/lipo "$app_dir/Contents/MacOS/Air75AgentBridge" -verify_arch "$arch_value"
done

# The app doesn't record audio or open network sockets. Input Monitoring,
# Accessibility and HID access are user-approved TCC capabilities, not code
# signing entitlements. Signing without an unnecessary entitlement blob also
# prevents Gatekeeper from rejecting a malformed or over-broad declaration.
codesign_args=(--force --sign "$identity_value" --options runtime)
if [[ "$identity_value" == "N Agent Bridge Local Signing" ]]; then
  codesign_args+=(--timestamp=none)
elif [[ "$identity_value" != "-" ]]; then
  codesign_args+=(--timestamp)
fi
codesign "${codesign_args[@]}" "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
codesign -d -r- "$app_dir" 2>&1
echo "Built $release_kind App (${archs[*]}): $app_dir"
