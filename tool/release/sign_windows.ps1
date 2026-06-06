param(
  [Parameter(Mandatory = $true)]
  [string] $BundleDir
)

$ErrorActionPreference = "Stop"

function Require-Env([string] $Name) {
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    Write-Error "$Name is required for Windows release signing."
    exit 64
  }
  return $value
}

$certificateBase64 = Require-Env "WINDOWS_CERTIFICATE_PFX_BASE64"
$certificatePassword = Require-Env "WINDOWS_CERTIFICATE_PASSWORD"
$timestampUrl = [Environment]::GetEnvironmentVariable("WINDOWS_TIMESTAMP_URL")
if ([string]::IsNullOrWhiteSpace($timestampUrl)) {
  $timestampUrl = "http://timestamp.digicert.com"
}

if (-not (Test-Path $BundleDir)) {
  Write-Error "Missing Windows bundle directory: $BundleDir"
  exit 1
}

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe |
  Sort-Object FullName -Descending |
  Select-Object -First 1
if ($null -eq $signtool) {
  Write-Error "signtool.exe was not found."
  exit 1
}

$tempRoot = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
  [IO.Path]::GetTempPath()
} else {
  $env:RUNNER_TEMP
}
$pfxPath = Join-Path $tempRoot "alera-signing.pfx"
[IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($certificateBase64))

$targets = Get-ChildItem $BundleDir -Recurse -File |
  Where-Object { $_.Extension -in ".exe", ".dll", ".msi" }
if ($targets.Count -eq 0) {
  Write-Error "No Windows binaries found to sign in $BundleDir"
  exit 1
}

foreach ($target in $targets) {
  & $signtool.FullName sign /fd SHA256 /tr $timestampUrl /td SHA256 /f $pfxPath /p $certificatePassword $target.FullName
  & $signtool.FullName verify /pa /all $target.FullName
}
