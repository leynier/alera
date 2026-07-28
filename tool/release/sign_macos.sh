#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:?bundle directory is required}"
app_path="${2:-$bundle_dir/Alera.app}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "::error::$name is required for macOS release signing." >&2
    exit 64
  fi
}

require_env APPLE_DEVELOPER_ID_APPLICATION
require_env APPLE_DEVELOPER_ID_TEAM_ID
require_env APPLE_CERTIFICATE_P12_BASE64
require_env APPLE_CERTIFICATE_PASSWORD
require_env APPLE_ID
require_env APPLE_APP_SPECIFIC_PASSWORD

base64_decode() {
  if base64 --decode >/dev/null 2>&1 <<<""; then
    base64 --decode
  else
    base64 -D
  fi
}

if [[ ! -d "$app_path" ]]; then
  echo "::error::Missing macOS app bundle: $app_path" >&2
  exit 1
fi

tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
mkdir -p "$tmp_root"
keychain="$tmp_root/alera-release-signing.keychain-db"
security create-keychain -p "$APPLE_CERTIFICATE_PASSWORD" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$APPLE_CERTIFICATE_PASSWORD" "$keychain"
existing_keychains=()
while IFS= read -r existing_keychain; do
  if [[ -n "$existing_keychain" ]]; then
    existing_keychains+=("$existing_keychain")
  fi
done < <(security list-keychains -d user | tr -d '"')
security list-keychains -d user -s "$keychain" "${existing_keychains[@]}"

cert_path="$tmp_root/alera-developer-id.p12"
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64_decode >"$cert_path"
security import "$cert_path" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$APPLE_CERTIFICATE_PASSWORD" "$keychain"

identity="$APPLE_DEVELOPER_ID_APPLICATION"
entitlements="macos/Runner/Release.entitlements"

sign_macho_files() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    return
  fi
  while IFS= read -r binary; do
    if file -b "$binary" | grep -q "Mach-O"; then
      codesign --force --options runtime --timestamp --sign "$identity" "$binary"
    fi
  done < <(find "$root" -type f -print | sort)
}

sign_macho_files "$app_path/Contents/Frameworks"
sign_macho_files "$app_path/Contents/Resources/alera"

# Developer ID signing changes the source-built serve-sim binary. Refresh its
# derived SHA before the outer app signature seals the helper manifest.
dart tool/native_helpers/refresh_signed_native_helper_bundle.dart \
  --emulator-root "$app_path/Contents/Resources/alera/emulator"

# A framework is a nested code bundle, so sign the bundle after its Mach-O and
# before the outer app. Apple recommends using --deep for verification only.
while IFS= read -r framework; do
  codesign --force --options runtime --timestamp --sign "$identity" "$framework"
done < <(find "$app_path/Contents/Frameworks" -type d -name "*.framework" -print 2>/dev/null | sort -r)

codesign --force --options runtime --timestamp \
  --entitlements "$entitlements" \
  --sign "$identity" \
  "$app_path"

codesign --verify --strict --deep --verbose=2 "$app_path"

zip_path="$tmp_root/Alera-notarization.zip"
ditto -c -k --keepParent "$app_path" "$zip_path"
xcrun notarytool submit "$zip_path" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_DEVELOPER_ID_TEAM_ID" \
  --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl -a -t exec -vv "$app_path"
