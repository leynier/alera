# Behavior checks for tool/development/setup_windows_vulkan.ps1. Run by
# test/unit/windows_setup_script_test.dart when pwsh is on PATH; exits non-zero
# on the first failed expectation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\tool\development\setup_windows_vulkan.ps1')

$version = '1.4.350.0'
$root = Join-Path ([System.IO.Path]::GetTempPath()) "alera-vulkan-test-$([guid]::NewGuid().ToString('N'))"

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) {
        throw "${Name}: expected [$Expected], got [$Actual]"
    }
    Write-Host "ok - $Name"
}

function New-FakeSdk([string]$Directory) {
    foreach ($file in @(
        [System.IO.Path]::Combine($Directory, 'Lib', 'vulkan-1.lib'),
        [System.IO.Path]::Combine($Directory, 'Bin', 'glslc.exe')
    )) {
        New-Item -ItemType File -Force -Path $file | Out-Null
    }
    return (Resolve-Path -LiteralPath $Directory).Path
}

try {
    New-Item -ItemType Directory -Path $root | Out-Null
    $required = Join-Path $root $version

    Assert-Equal (Get-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @()) $null 'missing SDK is not found'

    # Issue 850: with VULKAN_SDK unset and one install on disk, the candidate
    # list used to collapse into one concatenated string.
    $expected = New-FakeSdk $required
    Assert-Equal (Get-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @($null, '')) $expected 'finds the SDK without VULKAN_SDK'

    $other = New-FakeSdk (Join-Path $root 'custom')
    Assert-Equal (Get-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @($other)) $other 'prefers VULKAN_SDK'
    Assert-Equal (Get-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @((Join-Path $root 'absent'))) $expected 'falls back past a stale VULKAN_SDK'

    Remove-Item -LiteralPath ([System.IO.Path]::Combine($required, 'Bin', 'glslc.exe'))
    Remove-Item -LiteralPath $other -Recurse
    Assert-Equal (Get-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @()) $null 'requires glslc'

    # Issue 850: winget returns while the installer is still unpacking.
    $script:polls = 0
    $installerRunning = {
        $script:polls++
        if ($script:polls -eq 3) {
            New-FakeSdk $required | Out-Null
        }
        return $script:polls -lt 5
    }
    $found = Wait-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @() -Timeout ([TimeSpan]::FromSeconds(30)) -PollInterval ([TimeSpan]::FromMilliseconds(10)) -IsInstallerRunning $installerRunning
    Assert-Equal $found $expected 'waits for the installer to finish'
    Assert-Equal $script:polls 5 'does not accept the SDK while the installer runs'

    Remove-Item -LiteralPath ([System.IO.Path]::Combine($required, 'Bin', 'glslc.exe'))
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $found = Wait-VulkanSdkDirectory -RequiredVersion $version -SdkRoot $root -PreferredDirectories @() -Timeout ([TimeSpan]::FromMilliseconds(200)) -PollInterval ([TimeSpan]::FromMilliseconds(20)) -IsInstallerRunning { $false }
    Assert-Equal $found $null 'gives up after the timeout'
    Assert-Equal ($stopwatch.Elapsed -lt [TimeSpan]::FromSeconds(10)) $true 'timeout is bounded'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
