#!/usr/bin/env bash
set -euo pipefail

required=(
  APPLE_DEVELOPER_ID_APPLICATION
  APPLE_DEVELOPER_ID_TEAM_ID
  APPLE_CERTIFICATE_P12_BASE64
  APPLE_CERTIFICATE_PASSWORD
  APPLE_ID
  APPLE_APP_SPECIFIC_PASSWORD
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "::warning::Apple Developer ID credentials are incomplete; packaging an unsigned macOS release."
    exit 0
  fi
done

app_path="${DESKTOP_UPDATER_APP_PATH:?DESKTOP_UPDATER_APP_PATH is required}"
bash tool/release/sign_macos.sh "$(dirname "$app_path")" "$app_path"
