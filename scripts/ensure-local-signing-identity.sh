#!/bin/zsh
set -euo pipefail

identity_name="N Agent Bridge Local Signing"
login_keychain="$HOME/Library/Keychains/login.keychain-db"
script_dir=${0:A:h}
project_dir=${script_dir:h}
openssl_config="$project_dir/Distribution/LocalCodeSigning.openssl.cnf"

if security find-identity -v -p codesigning "$login_keychain" 2>/dev/null | grep -Fq "\"$identity_name\""; then
  echo "Local signing identity already available: $identity_name"
  exit 0
fi

existing_certificate=$(security find-certificate -a -Z -c "$identity_name" "$login_keychain" 2>/dev/null || true)
if [[ -n "$existing_certificate" ]]; then
  echo "A certificate named '$identity_name' exists but is not a valid code-signing identity." >&2
  echo "Remove that incomplete certificate in Keychain Access before retrying." >&2
  exit 2
fi

temporary_dir=$(mktemp -d /tmp/n-agent-bridge-local-signing.XXXXXX)
cleanup() { /bin/rm -rf "$temporary_dir"; }
trap cleanup EXIT

private_key="$temporary_dir/private-key.pem"
certificate="$temporary_dir/certificate.pem"
archive="$temporary_dir/identity.p12"
archive_password=$(openssl rand -hex 24)

openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
  -keyout "$private_key" -out "$certificate" -config "$openssl_config"
openssl pkcs12 -export -inkey "$private_key" -in "$certificate" \
  -out "$archive" -passout "pass:$archive_password"

security import "$archive" -k "$login_keychain" -f pkcs12 -P "$archive_password" \
  -T /usr/bin/codesign -T /usr/bin/security

# Some macOS releases already accept a self-signed identity stored in the
# user's login keychain. Only ask the system to add explicit codeSign trust
# when the identity is not yet considered valid.
if ! security find-identity -v -p codesigning "$login_keychain" | grep -Fq "\"$identity_name\""; then
  security add-trusted-cert -r trustRoot -p codeSign -k "$login_keychain" "$certificate"
fi

if ! security find-identity -v -p codesigning "$login_keychain" | grep -Fq "\"$identity_name\""; then
  echo "The local code-signing identity was imported but did not validate." >&2
  exit 3
fi

echo "Created stable local signing identity: $identity_name"
