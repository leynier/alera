[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FixturePath,
    [ValidateRange(1, 120)]
    [int]$CaseTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This test runner requires Windows and Git Bash.'
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$fixturePath = [IO.Path]::GetFullPath($FixturePath)
$fixtureRoot = [IO.Path]::GetDirectoryName($fixturePath)
$fixture = [IO.File]::ReadAllText($fixturePath, $utf8) | ConvertFrom-Json
$scriptPath = [IO.Path]::GetFullPath($fixture.scriptPath)
if (-not $scriptPath.StartsWith($fixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The generated hook script must belong to the fixture directory.'
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($scriptPath))
[IO.File]::WriteAllText($scriptPath, $fixture.scriptContent, $utf8)
Write-Verbose 'Generated fixture loaded.'

$bashCandidates = @(
    $env:CLAUDE_CODE_GIT_BASH_PATH
    (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe')
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
)
$bash = $bashCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $bash) {
    throw 'Git-for-Windows bash.exe is required; WSL bash.exe is not supported.'
}
$bashDirectory = [IO.Path]::GetDirectoryName($bash)
$msysRuntime = Join-Path $bashDirectory 'msys-2.0.dll'
$bundledRuntime = Join-Path ([IO.Path]::GetDirectoryName($bashDirectory)) 'usr\bin\msys-2.0.dll'
if (-not (Test-Path -LiteralPath $msysRuntime) -and -not (Test-Path -LiteralPath $bundledRuntime)) {
    throw 'The selected bash.exe does not belong to Git for Windows.'
}

$expectedFields = @{
    terminalSessionId = 'fixture-session'
    workspaceId = 'fixture-workspace'
    tabId = 'fixture-tab'
    hookEventName = 'PostToolUse'
    version = '1'
}
if ($fixture.expectedFields) {
    foreach ($property in $fixture.expectedFields.PSObject.Properties) {
        $expectedFields[$property.Name] = $property.Value
    }
}

function Set-FixtureStreamDeadline([IO.Stream]$Stream, [Diagnostics.Stopwatch]$Elapsed) {
    $remaining = $CaseTimeoutSeconds - $Elapsed.Elapsed.TotalSeconds
    if ($remaining -le 0) { throw 'Hook HTTP request exceeded the fixture deadline.' }
    $milliseconds = [int][Math]::Max(1, [Math]::Min(5000, $remaining * 1000))
    $Stream.ReadTimeout = $milliseconds
    $Stream.WriteTimeout = $milliseconds
}

function Read-HookRequest([Net.Sockets.TcpClient]$Client, [Diagnostics.Stopwatch]$Elapsed) {
    Write-Verbose 'Reading hook HTTP headers.'
    $Client.NoDelay = $true
    $stream = $Client.GetStream()
    $reader = [IO.BufferedStream]::new($stream, 8192)
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 5000
    $headerBytes = New-Object 'System.Collections.Generic.List[byte]'
    while ($true) {
        if ($headerBytes.Count % 256 -eq 0) { Set-FixtureStreamDeadline $stream $Elapsed }
        $next = $reader.ReadByte()
        if ($next -lt 0) { throw 'Hook disconnected before sending HTTP headers.' }
        $headerBytes.Add([byte]$next)
        if ($headerBytes.Count -gt 32768) { throw 'Hook HTTP headers exceed the fixture limit.' }
        $count = $headerBytes.Count
        if ($count -ge 4 -and $headerBytes[$count - 4] -eq 13 -and $headerBytes[$count - 3] -eq 10 -and $headerBytes[$count - 2] -eq 13 -and $headerBytes[$count - 1] -eq 10) { break }
    }
    $headers = [Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
    Write-Verbose 'Hook HTTP headers received.'
    if ($headers -notmatch '(?im)^POST /hook/claude HTTP/1\.[01]\r?$') { throw 'Hook did not POST to /hook/claude.' }
    if ($headers -notmatch '(?im)^X-Alera-Agent-Hook-Token: fixture-token\r?$') { throw 'Hook authentication token was not refreshed from endpoint data.' }
    if ($headers -notmatch '(?im)^Content-Type: application/json(?:;[^\r\n]*)?\r?$') { throw 'Hook did not send JSON.' }
    if ($headers -notmatch '(?im)^Content-Length: ([0-9]+)\r?$') { throw 'Hook omitted Content-Length.' }
    $length = [int]$Matches[1]
    if ($length -gt 1048576) { throw 'Hook payload exceeds the fixture limit.' }
    if ($headers -match '(?im)^Expect: 100-continue\r?$') {
        Set-FixtureStreamDeadline $stream $Elapsed
        $continue = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 100 Continue`r`n`r`n")
        $stream.Write($continue, 0, $continue.Length)
    }
    $body = New-Object byte[] $length
    $offset = 0
    while ($offset -lt $length) {
        Set-FixtureStreamDeadline $stream $Elapsed
        $read = $reader.Read($body, $offset, $length - $offset)
        if ($read -eq 0) { throw 'Hook disconnected before sending its complete body.' }
        $offset += $read
    }
    Write-Verbose 'Hook HTTP body received.'
    Set-FixtureStreamDeadline $stream $Elapsed
    $response = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`n{}")
    $stream.Write($response, 0, $response.Length)
    $reader.Dispose()
    $Client.Dispose()
    Write-Verbose 'Hook HTTP response sent.'
    return ($utf8.GetString($body) | ConvertFrom-Json)
}

function Stop-FixtureProcess([Diagnostics.Process]$Process, [bool]$PipesOpen) {
    try { $exited = $Process.HasExited } catch [InvalidOperationException] { return }
    if ($exited) {
        if (-not $PipesOpen) { return }
        # MSYS exec can replace its Windows PID. Find only this fixture's script.
        $ownedPath = $scriptPath.Replace('\', '/')
        $orphans = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
            $_.CommandLine -and $_.CommandLine.Replace('\', '/').IndexOf($ownedPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        foreach ($orphan in $orphans) {
            & taskkill.exe /PID $orphan.ProcessId /T /F 2>$null | Out-Null
        }
        return
    }
    if (-not $exited) {
        $killInfo = New-Object Diagnostics.ProcessStartInfo
        $killInfo.FileName = 'taskkill.exe'
        $killInfo.Arguments = "/PID $($Process.Id) /T /F"
        $killInfo.UseShellExecute = $false
        $killInfo.CreateNoWindow = $true
        $killInfo.RedirectStandardOutput = $true
        $killInfo.RedirectStandardError = $true
        $killer = [Diagnostics.Process]::Start($killInfo)
        if (-not $killer.WaitForExit(5000)) { $killer.Kill() }
        $killer.Dispose()
        [void]$Process.WaitForExit(5000)
    }
}

function Write-HookFailureDiagnostics([Diagnostics.ProcessStartInfo]$Info, [Net.Sockets.TcpListener]$Listener) {
    # Replay a separate copy only after acceptance failed. Never turn it into a pass.
    $diagnosticPath = $scriptPath + '.diagnostic.ps1'
    $diagnosticCommand = [string]$fixture.command
    $diagnosticCommand = $diagnosticCommand.Replace([IO.Path]::GetFileName($scriptPath), [IO.Path]::GetFileName($diagnosticPath))
    $preamble = @'
[Console]::Error.WriteLine('Diagnostic PowerShell: ' + $PSVersionTable.PSVersion)
[Console]::Error.WriteLine('Diagnostic PSHOME: ' + $PSHOME)
[Console]::Error.WriteLine('Diagnostic PSModulePath: ' + $env:PSModulePath)
[Console]::Error.WriteLine('Diagnostic WinPSModulePath: ' + $env:WinPSModulePath)
[Console]::Error.WriteLine('Diagnostic BASH_ENV present: ' + (-not [string]::IsNullOrEmpty($env:BASH_ENV)))
[Console]::Error.WriteLine('Diagnostic endpoint exists: ' + [IO.File]::Exists($env:ALERA_AGENT_HOOK_ENDPOINT))
[Console]::Error.WriteLine('Diagnostic Claude guard: ' + (-not [string]::IsNullOrEmpty($env:CLAUDECODE)))
[Console]::Error.WriteLine('Diagnostic Grok guard: ' + (-not [string]::IsNullOrEmpty($env:GROK_HOOK_EVENT)))
'@
    $content = [string]$fixture.scriptContent
    $lineEnd = $content.IndexOf("`n") + 1
    $content = $content.Insert($lineEnd, $preamble + "`n")
    $content = $content.Replace('} catch {}', '} catch { [Console]::Error.WriteLine($_.Exception.ToString()); [Console]::Error.WriteLine($_.ScriptStackTrace) }')
    [IO.File]::WriteAllText($diagnosticPath, $content, $utf8)
    $originalCommand = $Info.EnvironmentVariables['ALERA_ACCEPTANCE_COMMAND']
    $process = New-Object Diagnostics.Process
    $stdout = $null
    $stderr = $null
    try {
        Write-Host ('Failed hook diagnostics through ' + $bash)
        $Info.EnvironmentVariables['ALERA_ACCEPTANCE_COMMAND'] = $diagnosticCommand
        $process.StartInfo = $Info
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $elapsed = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.HasExited -and $elapsed.Elapsed.TotalSeconds -lt 15) {
            if ($Listener.Pending()) {
                $client = $Listener.AcceptTcpClient()
                try { Read-HookRequest $client $elapsed | Out-Null } finally { $client.Dispose() }
            } else {
                [Threading.Thread]::Sleep(10)
            }
        }
        if (-not $process.HasExited) { Stop-FixtureProcess $process $true }
        if ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            Write-Host $stdout.Result
            Write-Host $stderr.Result
        }
    } catch {
        Write-Warning ('Hook diagnostics failed: ' + $_.Exception.Message)
    } finally {
        $pipesOpen = ($stdout -and -not $stdout.IsCompleted) -or ($stderr -and -not $stderr.IsCompleted)
        Stop-FixtureProcess $process $pipesOpen
        $process.Dispose()
        $Info.EnvironmentVariables['ALERA_ACCEPTANCE_COMMAND'] = $originalCommand
        [IO.File]::Delete($diagnosticPath)
    }
}

function Invoke-HookCase([string]$Mode, [string]$CaseName, [string]$Payload, [bool]$ExpectRequest) {
    Write-Verbose "Preparing $Mode / $CaseName."
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $caseRoot = Join-Path $workRoot ($Mode + '-' + $CaseName)
    [void][IO.Directory]::CreateDirectory($caseRoot)
    $stdinPath = Join-Path $caseRoot 'stdin.utf8'
    [IO.File]::WriteAllText($stdinPath, $Payload, $utf8)
    $endpointDirectory = Join-Path $caseRoot 'agent-hooks'
    [void][IO.Directory]::CreateDirectory($endpointDirectory)
    $endpointPath = Join-Path $endpointDirectory 'endpoint.cmd'
    $endpoint = @(
        "set ALERA_AGENT_HOOK_PORT=$port"
        'set ALERA_AGENT_HOOK_TOKEN=fixture-token'
        "set ALERA_AGENT_HOOK_VERSION=$($expectedFields.version)"
        'set ALERA_WORKSPACE_ID=forged-workspace'
        'set ALERA_AGENT_HOOK_EVENT=Injected'
        'echo INJECTED > endpoint-executed'
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($endpointPath, $endpoint, $utf8)

    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $bash
    # Keep Bash alive across MSYS exec so the deadline owns the hook's lifetime.
    # .NET Framework's stdin writer can emit a BOM before raw BaseStream writes.
    # Let Git Bash pipe the exact fixture bytes instead of creating that writer.
    $info.Arguments = '--noprofile --norc -c "/usr/bin/cat -- \"$ALERA_ACCEPTANCE_STDIN_PATH\" | eval \"$ALERA_ACCEPTANCE_COMMAND\"; hook_status=$?; exit \"$hook_status\""'
    $info.WorkingDirectory = $caseRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    foreach ($key in @('MSYS_NO_PATHCONV', 'MSYS2_ARG_CONV_EXCL', 'GROK_HOOK_EVENT', 'ALERA_AGENT_HOOK_ENDPOINT', 'ALERA_RUNTIME_DIR', 'TMUX', 'STY', 'ZELLIJ')) {
        [void]$info.EnvironmentVariables.Remove($key)
    }
    $variables = @{
        ALERA_ACCEPTANCE_COMMAND = [string]$fixture.command
        ALERA_ACCEPTANCE_STDIN_PATH = $stdinPath.Replace('\', '/')
        ALERA_AGENT_HOOK_ENDPOINT = $endpointPath
        ALERA_AGENT_HOOK_PORT = '1'
        ALERA_AGENT_HOOK_TOKEN = 'stale-token'
        ALERA_AGENT_HOOK_VERSION = 'stale-version'
        ALERA_TERMINAL_SESSION_ID = [string]$expectedFields.terminalSessionId
        ALERA_WORKSPACE_ID = [string]$expectedFields.workspaceId
        ALERA_TAB_ID = [string]$expectedFields.tabId
        CLAUDECODE = '1'
        CLAUDE_PID = '12345'
        CLAUDE_CONFIG_DIR = 'C:\fixture\claude-config'
        TMUX = 'fixture'
    }
    if ($expectedFields.claudeConfigDir) { $variables.CLAUDE_CONFIG_DIR = [string]$expectedFields.claudeConfigDir }
    if ($expectedFields.agentPid) { $variables.CLAUDE_PID = [string]$expectedFields.agentPid }
    foreach ($entry in $variables.GetEnumerator()) { $info.EnvironmentVariables[$entry.Key] = $entry.Value }
    if ($Mode -eq 'disabled') { $info.EnvironmentVariables['MSYS_NO_PATHCONV'] = '1' }
    if ($Mode -eq 'excluded') { $info.EnvironmentVariables['MSYS2_ARG_CONV_EXCL'] = '*' }
    switch ($CaseName) {
        'runtime-endpoint' {
            [void]$info.EnvironmentVariables.Remove('ALERA_AGENT_HOOK_ENDPOINT')
            $info.EnvironmentVariables['ALERA_RUNTIME_DIR'] = $caseRoot
        }
        'missing-identity' { [void]$info.EnvironmentVariables.Remove('ALERA_TAB_ID') }
        'not-claude' { [void]$info.EnvironmentVariables.Remove('CLAUDECODE') }
        'grok' { $info.EnvironmentVariables['GROK_HOOK_EVENT'] = 'PostToolUse' }
        'unreachable' { $listener.Stop() }
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $request = $null
    $stdout = $null
    $stderr = $null
    try {
        Write-Verbose 'Starting Git Bash.'
        [void]$process.Start()
        Write-Verbose "Git Bash started as $($process.Id)."
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        Write-Verbose 'Hook stdin supplied through a raw byte pipe.'
        $elapsed = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.HasExited -or ($CaseName -ne 'unreachable' -and $listener.Pending())) {
            if ($elapsed.Elapsed.TotalSeconds -gt $CaseTimeoutSeconds) { throw "Generated hook exceeded the $CaseTimeoutSeconds-second fixture deadline." }
            if ($CaseName -ne 'unreachable' -and $listener.Pending()) {
                if ($null -ne $request) { throw 'Generated hook sent more than one request.' }
                $client = $listener.AcceptTcpClient()
                try { $request = Read-HookRequest $client $elapsed } finally { $client.Dispose() }
            } else {
                [Threading.Thread]::Sleep(10)
            }
        }
        Write-Verbose 'Git Bash exited; draining hook output.'
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            throw 'Hook descendants kept an output pipe open after Git Bash exited.'
        }
        if ($process.ExitCode -ne 0) { throw "Generated hook exited with $($process.ExitCode): $($stderr.Result)" }
        if ($stdout.Result.Length -ne 0 -or $stderr.Result.Length -ne 0) { throw "Generated hook was not silent: $($stdout.Result) $($stderr.Result)" }
        if ($ExpectRequest) {
            if ($null -eq $request) {
                Write-HookFailureDiagnostics $info $listener
                throw "Generated hook did not reach the fixture receiver: $Mode / $CaseName."
            }
            foreach ($entry in $expectedFields.GetEnumerator()) {
                if ([string]$request.($entry.Key) -cne [string]$entry.Value) { throw "Hook field $($entry.Key) did not match the fixture." }
            }
            $expectedPayload = $Payload | ConvertFrom-Json
            if (($request.payload | ConvertTo-Json -Depth 100 -Compress) -cne ($expectedPayload | ConvertTo-Json -Depth 100 -Compress)) { throw 'Hook changed the JSON payload or its Unicode text.' }
        } elseif ($null -ne $request) {
            throw 'Generated hook reported a guarded or invalid payload.'
        }
        foreach ($marker in @('marker', 'endpoint-executed')) {
            if (Test-Path -LiteralPath (Join-Path $caseRoot $marker)) { throw "Hook executed input and created $marker." }
        }
        Write-Host "Claude hook accepted: $Mode / $CaseName"
    } finally {
        Write-Verbose 'Stopping owned hook processes.'
        $pipesOpen = ($stdout -and -not $stdout.IsCompleted) -or ($stderr -and -not $stderr.IsCompleted)
        Stop-FixtureProcess $process $pipesOpen
        $process.Dispose()
        $listener.Stop()
    }
}

$workRoot = Join-Path $fixtureRoot ('acceptance-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workRoot)
try {
    $text = '" > marker & echo INJECTED & rem " | ' + [char]0x00e1 + [char]0x96ea + [char]0xd83d + [char]0xde80
    $payload = @{ session_id = 'fixture-conversation'; tool_response = @{ text = $text }; number = 42 } | ConvertTo-Json -Depth 100 -Compress
    $payload = $payload.Replace('\u003e', '>').Replace('\u0026', '&')
    foreach ($mode in @('default', 'disabled', 'excluded')) {
        Invoke-HookCase $mode 'valid-json' $payload $true
        Invoke-HookCase $mode 'runtime-endpoint' $payload $true
        Invoke-HookCase $mode 'raw-stdin' "> marker & echo INJECTED`r`n" $false
        Invoke-HookCase $mode 'missing-identity' $payload $false
        Invoke-HookCase $mode 'not-claude' $payload $false
        Invoke-HookCase $mode 'grok' $payload $false
        Invoke-HookCase $mode 'unreachable' $payload $false
    }
    Write-Host 'Claude hook acceptance passed: 21 cases.'
} finally {
    if ([IO.Directory]::Exists($workRoot)) { [IO.Directory]::Delete($workRoot, $true) }
}
