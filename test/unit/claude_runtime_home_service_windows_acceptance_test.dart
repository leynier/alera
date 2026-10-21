import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Allow cold PowerShell startup as well as each case's bounded HTTP request.
const _runnerTimeout = Duration(minutes: 12);
const _cleanupTimeout = Duration(seconds: 10);

void main() {
  test(
    'generated Claude hooks post through real Git Bash on Windows',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'alera-dart-claude-native-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final home = Directory(
        p.join(root.path, r"Mira's $HOME (niño) & company"),
      )..createSync();
      final fixture = File(p.join(root.path, 'fixture.json'))
        ..writeAsStringSync(
          jsonEncode(
            await _generateFixture(
              home.path,
              Directory(p.join(root.path, 'support')),
            ),
          ),
        );
      final process = await Process.start('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join(
          Directory.current.path,
          'tool',
          'ci',
          'test_windows_claude_hooks.ps1',
        ),
        '-FixturePath',
        fixture.path,
      ]);
      final output = _ProcessOutput(process.stdout);
      final errors = _ProcessOutput(process.stderr);
      int? exitCode;
      Object? terminationError;
      try {
        await process.stdin.close();
        try {
          exitCode = await process.exitCode.timeout(_runnerTimeout);
        } on TimeoutException {
          try {
            await _terminateRunnerTree(process);
          } catch (error) {
            terminationError = error;
          }
        }
      } finally {
        await Future.wait<void>([output.drain(), errors.drain()]);
      }

      expect(
        exitCode,
        0,
        reason: <String>[
          if (exitCode == null)
            'Windows Claude hook acceptance runner timed out after '
                '${_runnerTimeout.inMinutes} minutes.',
          if (terminationError != null)
            'Failed to stop the runner process tree: $terminationError',
          '$output',
          '$errors',
        ].join('\n'),
      );
      expect(
        output.failed || errors.failed,
        isFalse,
        reason: '$output\n$errors',
      );
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 14)),
  );

  final fixturePath = Platform.environment['ALERA_WINDOWS_CLAUDE_FIXTURE_PATH'];
  final targetScriptPath =
      Platform.environment['ALERA_WINDOWS_CLAUDE_SCRIPT_PATH'];
  test(
    'exports generated Windows Claude hook fixture from Linux',
    () async {
      expect(
        fixturePath,
        isNotNull,
        reason: 'Set ALERA_WINDOWS_CLAUDE_FIXTURE_PATH and ALERA_WINDOWS_CLAUDE_SCRIPT_PATH together.',
      );
      expect(
        targetScriptPath,
        isNotNull,
        reason: 'Set ALERA_WINDOWS_CLAUDE_FIXTURE_PATH and ALERA_WINDOWS_CLAUDE_SCRIPT_PATH together.',
      );
      final nativeScriptPath = p.windows
          .normalize(targetScriptPath!)
          .replaceAll(r'\', '/');
      const scriptSuffix = '/.alera/agent-hooks/alera-claude-hook.ps1';
      expect(nativeScriptPath, matches(r'^[A-Za-z]:/'));
      expect(nativeScriptPath, endsWith(scriptSuffix));
      final nativeHome = nativeScriptPath.substring(
        0,
        nativeScriptPath.length - scriptSuffix.length,
      );
      final destination = File(fixturePath!).absolute;
      final originalDirectory = Directory.current;
      final simulation = await Directory.systemTemp.createTemp(
        'alera-claude-export-',
      );
      try {
        // A drive-qualified Windows path is relative on Linux, so all service
        // writes stay in the owned simulation while commands keep native paths.
        Directory.current = simulation;
        final fixture = await _generateFixture(
          nativeHome,
          Directory('support'),
        );
        expect(fixture['scriptPath'], nativeScriptPath);
        destination.parent.createSync(recursive: true);
        destination.writeAsStringSync(jsonEncode(fixture));
      } finally {
        Directory.current = originalDirectory;
        simulation.deleteSync(recursive: true);
      }
    },
    skip:
        !Platform.isLinux || (fixturePath == null && targetScriptPath == null),
  );
}

Future<void> _terminateRunnerTree(Process runner) async {
  Process? killer;
  try {
    // Killing only PowerShell leaves Git Bash and hook descendants alive.
    killer = await Process.start('taskkill.exe', <String>[
      '/PID',
      '${runner.pid}',
      '/T',
      '/F',
    ], mode: ProcessStartMode.inheritStdio);
    final exitCode = await killer.exitCode.timeout(_cleanupTimeout);
    if (exitCode != 0) {
      throw StateError('taskkill.exe exited with $exitCode.');
    }
  } finally {
    try {
      if (killer != null) {
        killer.kill();
        await killer.exitCode.timeout(_cleanupTimeout);
      }
    } finally {
      runner.kill();
      await runner.exitCode.timeout(_cleanupTimeout);
    }
  }
}

class _ProcessOutput {
  _ProcessOutput(Stream<List<int>> stream) {
    _subscription = stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          _buffer.write,
          onError: (Object error) {
            failed = true;
            _buffer.writeln('Failed to read process output: $error');
          },
          onDone: _done.complete,
        );
  }

  final _buffer = StringBuffer();
  final _done = Completer<void>();
  late final StreamSubscription<String> _subscription;
  bool failed = false;

  Future<void> drain() async {
    try {
      await _done.future.timeout(
        _cleanupTimeout,
        onTimeout: () {
          failed = true;
          _buffer.writeln(
            'Process output did not close before cleanup deadline.',
          );
        },
      );
    } finally {
      await _subscription.cancel().timeout(_cleanupTimeout);
    }
  }

  @override
  String toString() => _buffer.toString();
}

Future<Map<String, Object?>> _generateFixture(
  String homePath,
  Directory support,
) async {
  final service = ClaudeRuntimeHomeService(
    homeDirectory: homePath,
    applicationSupportDirectory: () async => support,
    platform: .windows,
    environment: <String, String>{'USERPROFILE': homePath},
    syncMacOSKeychainCredentials: false,
  );
  final preparation = await service.prepareForTerminalLaunch();
  final settings = jsonDecode(
    File(p.join(preparation.runtimeHomePath, 'settings.json'))
        .readAsStringSync(),
  ) as Map;
  final definition =
      ((settings['hooks'] as Map)['PreToolUse'] as List).single as Map;
  final command =
      (((definition['hooks'] as List).single as Map)['command']) as String;
  final scriptPath = p.join(
    homePath,
    '.alera',
    'agent-hooks',
    'alera-claude-hook.ps1',
  );
  return <String, Object?>{
    'command': command,
    'scriptPath': scriptPath,
    'scriptContent': File(scriptPath).readAsStringSync(),
    'expectedFields': <String, String>{
      'terminalSessionId': 'dart-terminal-ñ',
      'workspaceId': 'dart-workspace-漢字',
      'tabId': 'dart-tab-😀',
      'hookEventName': 'PreToolUse',
      'version': '1',
      'claudeConfigDir': p.join(
        homePath,
        '.ccs',
        'instances',
        'native-profile',
      ),
      'agentPid': '4242',
      'multiplexer': 'tmux',
    },
  };
}
