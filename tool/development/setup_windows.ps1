[CmdletBinding()]
param(
    [switch]$InstallMissingTools,
    [switch]$CheckOnly,
    [switch]$SkipNativePreflight
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$requiredFlutterVersion = [version]'3.44.8'
$minimumDartVersion = [version]'3.12.1'
$requiredZigVersion = [version]'0.16.0'
$requiredRustToolchain = '1.96'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory = $repoRoot) {
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath exited with code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Refresh-ProcessPath {
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $entries = foreach ($source in @($env:PATH, $userPath, $machinePath)) {
        foreach ($entry in ($source -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($entry) -and $seen.Add($entry)) {
                $entry
            }
        }
    }
    $env:PATH = $entries -join ';'
}

function Get-RequiredCommand([string]$Name, [string]$InstallHint) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Missing $Name. $InstallHint"
    }
    return $command
}

function Install-UserTool(
    [string]$Name,
    [string]$WingetId,
    [string]$ScoopName,
    [switch]$Force
) {
    if (-not $Force -and (Get-Command $Name -ErrorAction SilentlyContinue)) {
        return
    }
    if (-not $InstallMissingTools) {
        throw "Missing $Name. Rerun with -InstallMissingTools or install it manually."
    }

    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    if ($null -ne $scoop) {
        Invoke-Native $scoop.Source @('install', $ScoopName)
        Refresh-ProcessPath
        return
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw "Missing $Name and neither Scoop nor WinGet is available to install it."
    }
    $arguments = @(
        'install', '--exact', '--id', $WingetId,
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    if ($Name -eq 'zig') {
        $arguments += @('--scope', 'user')
    }
    Invoke-Native $winget.Source $arguments
    Refresh-ProcessPath
}

function Get-LibClangDirectory {
    $candidates = @(
        $env:LIBCLANG_PATH,
        (Join-Path $env:USERPROFILE 'scoop\apps\llvm\current\bin'),
        (Join-Path $env:ProgramFiles 'LLVM\bin')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'libclang.dll')) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Get-LibClangIncludeDirectory([string]$libClangDirectory) {
    $llvmRoot = Split-Path -Parent $libClangDirectory
    $clangRoot = Join-Path $llvmRoot 'lib\clang'
    return Get-ChildItem -LiteralPath $clangRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'include' } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ 'stdbool.h') } |
        Select-Object -First 1
}

function Get-DartVersion([System.Management.Automation.CommandInfo]$Dart) {
    $output = (& $Dart.Source --version 2>&1 | Out-String).Trim()
    if ($output -notmatch '([0-9]+\.[0-9]+\.[0-9]+)') {
        throw "Could not parse Dart version from: $output"
    }
    return [version]$Matches[1]
}

function Get-FlutterVersion([System.Management.Automation.CommandInfo]$Flutter) {
    $output = (& $Flutter.Source --version --machine 2>&1 | Out-String).Trim()
    try {
        $metadata = $output | ConvertFrom-Json
        return [version]$metadata.frameworkVersion
    }
    catch {
        throw "Could not parse Flutter version metadata: $output"
    }
}

function Get-WindowsDesktopToolchain {
    $vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswherePath)) {
        throw 'Visual Studio Installer was not found. Install Visual Studio 2022 with the Desktop development with C++ workload.'
    }

    $installations = @(
        (& $vswherePath -latest -version '[17.0,18.0)' -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -format json | ConvertFrom-Json)
    )
    if ($installations.Count -eq 0) {
        throw 'Visual Studio 2022 with the Desktop development with C++ workload is required. Newer Visual Studio releases do not replace this Flutter toolchain requirement.'
    }

    $sdkIncludeRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
    $sdk = Get-ChildItem -LiteralPath $sdkIncludeRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $sdk) {
        throw 'A Windows 10 or 11 SDK is required by the Flutter Windows runner.'
    }

    $msvcToolsRoot = Join-Path $installations[0].installationPath 'VC\Tools\MSVC'
    $msvc = Get-ChildItem -LiteralPath $msvcToolsRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $msvc -or -not (Test-Path -LiteralPath (Join-Path $msvc.FullName 'include\vcruntime.h'))) {
        throw "The MSVC C++ headers were not found under $msvcToolsRoot. Repair the Visual Studio Desktop development with C++ workload."
    }

    return [pscustomobject]@{
        VisualStudio = $installations[0].displayName
        InstallPath = $installations[0].installationPath
        WindowsSdk = $sdk.Name
        WindowsSdkIncludeRoot = $sdk.FullName
        MsvcInclude = Join-Path $msvc.FullName 'include'
    }
}

if (-not $IsWindows) {
    throw 'This setup script only supports Windows.'
}

Set-Location $repoRoot
Refresh-ProcessPath

Write-Step 'Checking Flutter and Dart'
$flutter = Get-RequiredCommand 'flutter' "Install Flutter $requiredFlutterVersion or newer, then reopen PowerShell."
$dart = Get-RequiredCommand 'dart' 'Dart must come from the same Flutter SDK.'
$flutterVersion = Get-FlutterVersion $flutter
$dartVersion = Get-DartVersion $dart
if ($flutterVersion -lt $requiredFlutterVersion) {
    throw "Flutter $flutterVersion is too old. Alera requires Flutter $requiredFlutterVersion or newer."
}
if ($dartVersion -lt $minimumDartVersion) {
    throw "Dart $dartVersion is too old. Alera requires Dart $minimumDartVersion or newer; CI uses Flutter $requiredFlutterVersion."
}
Invoke-Native $flutter.Source @('--version')

Write-Step 'Checking the Windows desktop toolchain'
$desktopToolchain = Get-WindowsDesktopToolchain
Write-Host "$($desktopToolchain.VisualStudio): $($desktopToolchain.InstallPath)"
Write-Host "Windows SDK: $($desktopToolchain.WindowsSdk)"
$cmakeGenerator = 'Visual Studio 17 2022'
$env:CMAKE_GENERATOR = $cmakeGenerator
if (-not $CheckOnly) {
    [Environment]::SetEnvironmentVariable('CMAKE_GENERATOR', $cmakeGenerator, 'User')
}
Write-Host "CMAKE_GENERATOR=$cmakeGenerator"

Write-Step 'Checking Git and long-path support'
$git = Get-RequiredCommand 'git' 'Install Git for Windows and reopen PowerShell.'
Invoke-Native $git.Source @('--version')
if (-not $CheckOnly) {
    Invoke-Native $git.Source @('config', '--global', 'core.longpaths', 'true')
}
$longPaths = (& $git.Source config --get core.longpaths 2>$null | Out-String).Trim()
if ($longPaths -ne 'true') {
    throw 'Git long-path support is disabled. Run: git config --global core.longpaths true'
}

Write-Step 'Checking Rust, Zig, and LLVM'
$rustup = Get-RequiredCommand 'rustup' 'Install rustup from https://rustup.rs and reopen PowerShell.'
if (-not $CheckOnly) {
    Invoke-Native $rustup.Source @('toolchain', 'install', $requiredRustToolchain, '--profile', 'minimal', '--component', 'rustfmt', '--component', 'clippy')
}
else {
    Invoke-Native $rustup.Source @('run', $requiredRustToolchain, 'rustc', '--version')
}

if (-not $CheckOnly) {
    Install-UserTool 'zig' 'zig.zig' 'zig'
}
$zig = Get-RequiredCommand 'zig' 'Install Zig 0.16.0 and reopen PowerShell.'
$zigVersion = [version]((& $zig.Source version 2>&1 | Out-String).Trim())
if ($zigVersion -ne $requiredZigVersion) {
    throw "Zig $zigVersion is installed; Alera requires exactly $requiredZigVersion."
}

$libClangDirectory = Get-LibClangDirectory
if ($null -eq $libClangDirectory -and -not $CheckOnly) {
    Install-UserTool 'clang' 'LLVM.LLVM' 'llvm' -Force
    $libClangDirectory = Get-LibClangDirectory
}
if ($null -eq $libClangDirectory) {
    throw 'libclang.dll was not found. Install LLVM, then set LIBCLANG_PATH to its bin directory.'
}
$env:LIBCLANG_PATH = $libClangDirectory
$libClangIncludeDirectory = Get-LibClangIncludeDirectory $libClangDirectory
if ($null -eq $libClangIncludeDirectory) {
    throw "LLVM's Clang resource headers were not found next to $libClangDirectory."
}
$bindgenIncludeDirectories = @(
    $libClangIncludeDirectory,
    $desktopToolchain.MsvcInclude,
    (Join-Path $desktopToolchain.WindowsSdkIncludeRoot 'ucrt'),
    (Join-Path $desktopToolchain.WindowsSdkIncludeRoot 'shared'),
    (Join-Path $desktopToolchain.WindowsSdkIncludeRoot 'um'),
    (Join-Path $desktopToolchain.WindowsSdkIncludeRoot 'winrt'),
    (Join-Path $desktopToolchain.WindowsSdkIncludeRoot 'cppwinrt')
) | Where-Object { Test-Path -LiteralPath $_ }
$bindgenClangArguments = ($bindgenIncludeDirectories | ForEach-Object {
    $normalizedIncludeDirectory = $_.Replace('\', '/')
    "-I`"$normalizedIncludeDirectory`""
}) -join ' '
$env:BINDGEN_EXTRA_CLANG_ARGS = $bindgenClangArguments
if (-not $CheckOnly) {
    [Environment]::SetEnvironmentVariable('LIBCLANG_PATH', $libClangDirectory, 'User')
    [Environment]::SetEnvironmentVariable('BINDGEN_EXTRA_CLANG_ARGS', $bindgenClangArguments, 'User')
}
Write-Host "LIBCLANG_PATH=$libClangDirectory"
Write-Host "BINDGEN_EXTRA_CLANG_ARGS=$bindgenClangArguments"

if ($CheckOnly) {
    Write-Host "`nWindows prerequisites are ready." -ForegroundColor Green
    exit 0
}

Write-Step 'Enabling Flutter Windows desktop support'
Invoke-Native $flutter.Source @('config', '--enable-windows-desktop')

Write-Step 'Initializing required source submodules'
Invoke-Native $dart.Source @('tool/development/initialize_required_submodules.dart')

Write-Step 'Resolving Flutter dependencies'
Invoke-Native $flutter.Source @('pub', 'get')

Write-Step 'Applying native-asset compatibility patches'
Invoke-Native $dart.Source @('tool/ci/patch_native_asset_ci_workarounds.dart')

if (-not $SkipNativePreflight) {
    Write-Step 'Running the Windows native-asset preflight'
    Write-Host 'The first Ghostty source build can take several minutes without producing output.'
    Invoke-Native $flutter.Source @(
        'test', 'test/unit/native_asset_preflight_test.dart',
        '--name', 'native asset package graph is available'
    )
}

Write-Host "`nAlera is ready for Windows development." -ForegroundColor Green
Write-Host 'Run: flutter run -d windows'
Write-Host 'Optional make flow: make app-debug'
