# Vulkan SDK discovery for setup_windows.ps1. Dot-sourced by that script and by
# test/fixtures/setup_windows_vulkan_test.ps1; it defines functions only.

function Test-VulkanSdkDirectory([string]$Directory) {
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return $false
    }
    return (Test-Path -LiteralPath ([System.IO.Path]::Combine($Directory, 'Lib', 'vulkan-1.lib'))) -and
        (Test-Path -LiteralPath ([System.IO.Path]::Combine($Directory, 'Bin', 'glslc.exe')))
}

function Get-VulkanSdkDirectory {
    param(
        [Parameter(Mandatory)][string]$RequiredVersion,
        [string]$SdkRoot = 'C:\VulkanSDK',
        # The LunarG installer sets VULKAN_SDK machine-wide, which shells that
        # were already open do not see, so read the persisted scopes as well.
        [string[]]$PreferredDirectories = @(
            $env:VULKAN_SDK,
            [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'User'),
            [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'Machine')
        )
    )
    # A typed list: a filtered pipeline that yields one path is a scalar
    # string, and += on it concatenates instead of appending.
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in $PreferredDirectories) {
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            $candidates.Add($directory)
        }
    }
    $candidates.Add((Join-Path $SdkRoot $RequiredVersion))
    foreach ($directory in @(Get-ChildItem -LiteralPath $SdkRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $candidates.Add($directory.FullName)
    }

    foreach ($candidate in $candidates) {
        if (Test-VulkanSdkDirectory $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Test-VulkanSdkInstallerRunning {
    return $null -ne (Get-Process -Name 'vulkansdk-windows-*' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Wait-VulkanSdkDirectory {
    param(
        [Parameter(Mandatory)][string]$RequiredVersion,
        [string]$SdkRoot = 'C:\VulkanSDK',
        [string[]]$PreferredDirectories = @(
            $env:VULKAN_SDK,
            [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'User'),
            [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'Machine')
        ),
        [TimeSpan]$Timeout = [TimeSpan]::FromMinutes(10),
        [TimeSpan]$PollInterval = [TimeSpan]::FromSeconds(5),
        [scriptblock]$IsInstallerRunning = { Test-VulkanSdkInstallerRunning }
    )
    # winget returns once the LunarG launcher exits, while the installer is
    # still unpacking; glslc.exe appears only after that.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextReport = [TimeSpan]::FromSeconds(30)
    while ($true) {
        if (-not (& $IsInstallerRunning)) {
            $directory = Get-VulkanSdkDirectory -RequiredVersion $RequiredVersion -SdkRoot $SdkRoot -PreferredDirectories $PreferredDirectories
            if ($null -ne $directory) {
                return $directory
            }
        }
        if ($stopwatch.Elapsed -ge $Timeout) {
            return $null
        }
        if ($stopwatch.Elapsed -ge $nextReport) {
            Write-Host "Still waiting for the Vulkan SDK installer ($([int]$stopwatch.Elapsed.TotalSeconds) s)..."
            $nextReport += [TimeSpan]::FromSeconds(30)
        }
        Start-Sleep -Milliseconds ([int]$PollInterval.TotalMilliseconds)
    }
}
