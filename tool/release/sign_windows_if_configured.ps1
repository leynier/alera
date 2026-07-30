$ErrorActionPreference = "Stop"

$required = @(
  "WINDOWS_CERTIFICATE_PFX_BASE64",
  "WINDOWS_CERTIFICATE_PASSWORD"
)
foreach ($name in $required) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    Write-Output "::warning::Windows code-signing credentials are incomplete; packaging an unsigned Windows release."
    exit 0
  }
}

if ([string]::IsNullOrWhiteSpace($env:DESKTOP_UPDATER_APP_PATH)) {
  Write-Error "DESKTOP_UPDATER_APP_PATH is required."
  exit 64
}

pwsh -NoProfile -File tool/release/sign_windows.ps1 -BundleDir $env:DESKTOP_UPDATER_APP_PATH
