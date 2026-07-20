#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
identity_value=${AIR75_SIGNING_IDENTITY:-}
notary_profile=${AIR75_NOTARY_PROFILE:-}

if [[ -z ${AIR75_VERSION:-} || -z ${AIR75_BUILD_NUMBER:-} ]]; then
  echo "Set AIR75_VERSION and AIR75_BUILD_NUMBER for this public release." >&2
  exit 2
fi
if [[ "$identity_value" != "Developer ID Application:"* ]]; then
  echo "Set AIR75_SIGNING_IDENTITY to the full Developer ID Application identity." >&2
  exit 2
fi
if [[ -z "$notary_profile" ]]; then
  echo "Set AIR75_NOTARY_PROFILE to a notarytool Keychain profile." >&2
  exit 2
fi
if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity_value\""; then
  echo "Developer ID Application identity is not installed: $identity_value" >&2
  exit 2
fi
if ! command -v xcrun >/dev/null || ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "Apple notarytool is not installed." >&2
  exit 2
fi

export AIR75_RELEASE_KIND=distribution
export AIR75_RELEASE_ARCHS="arm64 x86_64"

"$script_dir/build-release.sh"
"$script_dir/create-dmg.sh"
"$script_dir/notarize-release.sh"
"$script_dir/verify-release.sh"

echo "Public release is Developer ID signed, notarized, stapled and verified."
