$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'This test runner requires Windows.'
}

# Cargo adds every native link-search directory to PATH when running tests.
# Whisper's CMake paths can exceed cmd.exe's 8191-character environment limit.
# Run the statically linked test artifact with the original runner environment.
Write-Host "Workflow test runner PATH length: $($env:PATH.Length)"
& cmd.exe /d /c 'git --version'
if ($LASTEXITCODE -ne 0) {
    throw 'The runner environment must resolve Git from cmd.exe before testing setup.'
}

$messages = @(& cargo test --manifest-path rust/Cargo.toml --locked `
    -p alera-cli --bin alera --no-run --message-format=json)
$buildExitCode = $LASTEXITCODE

$executables = @(
    foreach ($line in $messages) {
        $message = $line | ConvertFrom-Json
        if ($message.reason -eq 'compiler-message' -and $message.message.rendered) {
            Write-Host $message.message.rendered
        }
        if ($message.reason -eq 'compiler-artifact' -and
            $message.profile.test -and $message.target.name -eq 'alera' -and
            $message.executable) {
            $message.executable
        }
    }
)
if ($buildExitCode -ne 0) {
    throw "Workflow test compilation failed with exit code $buildExitCode."
}
if ($executables.Count -ne 1 -or -not (Test-Path -LiteralPath $executables[0] -PathType Leaf)) {
    throw 'Expected exactly one compiled alera test executable.'
}

& $executables[0] workflow_ --nocapture
exit $LASTEXITCODE
