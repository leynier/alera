import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserCommandEnvironmentResolver', () {
    test('parses shell PATH between delimiters and strips ANSI output', () {
      final segments = parseHydratedShellPath(
        '\x1B[32mbanner\x1B[0m\n'
        '$shellPathHydrationDelimiter'
        '/Users/test/.opencode/bin:/Users/test/.cargo/bin:/usr/bin:/Users/test/.cargo/bin'
        '$shellPathHydrationDelimiter\nprompt',
      );

      expect(segments, <String>[
        '/Users/test/.opencode/bin',
        '/Users/test/.cargo/bin',
        '/usr/bin',
      ]);
    });

    test('returns no parsed PATH when delimiters are missing', () {
      expect(parseHydratedShellPath('/usr/bin:/bin'), isEmpty);
      expect(
        parseHydratedShellPath('$shellPathHydrationDelimiter/usr/bin'),
        isEmpty,
      );
    });

    test(
      'prepends shell PATH segments without duplicating existing entries',
      () {
        final environment = <String, String>{'PATH': '/usr/bin:/bin'};

        final added = mergePathSegmentsForTesting(environment, <String>[
          '/Users/test/.opencode/bin',
          '/usr/bin',
          '/Users/test/.cargo/bin',
        ], isWindows: false);

        expect(added, <String>[
          '/Users/test/.opencode/bin',
          '/Users/test/.cargo/bin',
        ]);
        expect(
          environment['PATH'],
          '/Users/test/.opencode/bin:/Users/test/.cargo/bin:/usr/bin:/bin',
        );
      },
    );

    test(
      'hydrates POSIX shell PATH once and merges it into command environment',
      () async {
        var hydrateCount = 0;
        final resolver = UserCommandEnvironmentResolver(
          platformEnvironment: const <String, String>{
            'SHELL': '/bin/zsh',
            'PATH': '/usr/bin',
          },
          isWindows: false,
          isMacOS: true,
          hydrator: (shell) async {
            hydrateCount += 1;
            expect(shell, '/bin/zsh');
            return const CommandEnvironmentHydrationResult.success(<String>[
              '/Users/test/.opencode/bin',
              '/usr/bin',
            ]);
          },
        );

        final first = await resolver.environment();
        final second = await resolver.environment();

        expect(hydrateCount, 1);
        expect(first['PATH'], '/Users/test/.opencode/bin:/usr/bin');
        expect(second['PATH'], '/Users/test/.opencode/bin:/usr/bin');
      },
    );

    test(
      'falls back to platform environment when shell hydration is unavailable',
      () async {
        final resolver = UserCommandEnvironmentResolver(
          platformEnvironment: const <String, String>{'PATH': r'C:\Windows'},
          isWindows: true,
          hydrator: (_) async {
            throw StateError('hydrator must not run on Windows');
          },
        );

        final environment = await resolver.environment();

        expect(environment, <String, String>{'PATH': r'C:\Windows'});
      },
    );

    test('parses hydrated shell variables and skips empty values', () {
      final values = parseHydratedShellVariables(
        '\x1B[32mbanner\x1B[0m\n'
        '${shellVariableHydrationDelimiter}KIMI_API_KEY=secret-key'
        '$shellVariableHydrationDelimiter'
        '${shellVariableHydrationDelimiter}ZAI_API_KEY='
        '$shellVariableHydrationDelimiter'
        '${shellVariableHydrationDelimiter}OTHER=value'
        '$shellVariableHydrationDelimiter\nprompt',
        <String>['KIMI_API_KEY', 'ZAI_API_KEY'],
      );

      expect(values, <String, String>{'KIMI_API_KEY': 'secret-key'});
    });

    test('keeps equals signs inside hydrated variable values', () {
      final values = parseHydratedShellVariables(
        '${shellVariableHydrationDelimiter}TOKEN=abc==def'
        '$shellVariableHydrationDelimiter',
        <String>['TOKEN'],
      );

      expect(values, <String, String>{'TOKEN': 'abc==def'});
    });

    test('validates environment variable names before shell interpolation', () {
      expect(isValidEnvironmentVariableName('KIMI_API_KEY'), isTrue);
      expect(isValidEnvironmentVariableName('_private'), isTrue);
      expect(isValidEnvironmentVariableName('9LEADING'), isFalse);
      expect(isValidEnvironmentVariableName(''), isFalse);
      expect(isValidEnvironmentVariableName(r'X; rm -rf $HOME'), isFalse);
      expect(isValidEnvironmentVariableName('A B'), isFalse);
    });

    test(
      'hydrates shell variables once per name set and skips Windows',
      () async {
        var hydrateCount = 0;
        final resolver = UserCommandEnvironmentResolver(
          platformEnvironment: const <String, String>{'SHELL': '/bin/zsh'},
          isWindows: false,
          isMacOS: true,
          variablesHydrator: (shell, names) async {
            hydrateCount += 1;
            expect(shell, '/bin/zsh');
            expect(names, <String>['KIMI_API_KEY']);
            return <String, String>{'KIMI_API_KEY': 'secret'};
          },
        );

        // Invalid names are dropped before reaching the hydrator.
        final first = await resolver.environmentVariables(<String>[
          'KIMI_API_KEY',
          'bad name',
        ]);
        final second = await resolver.environmentVariables(<String>[
          'KIMI_API_KEY',
        ]);

        expect(hydrateCount, 1);
        expect(first, <String, String>{'KIMI_API_KEY': 'secret'});
        expect(second, <String, String>{'KIMI_API_KEY': 'secret'});

        final windowsResolver = UserCommandEnvironmentResolver(
          platformEnvironment: const <String, String>{},
          isWindows: true,
          variablesHydrator: (_, _) async {
            throw StateError('hydrator must not run on Windows');
          },
        );
        expect(
          await windowsResolver.environmentVariables(<String>['KIMI_API_KEY']),
          isEmpty,
        );
      },
    );

    test(
      'falls back to platform environment when shell hydration fails',
      () async {
        final resolver = UserCommandEnvironmentResolver(
          platformEnvironment: const <String, String>{
            'SHELL': '/bin/zsh',
            'PATH': '/usr/bin',
          },
          isWindows: false,
          isMacOS: true,
          hydrator: (_) async {
            return const CommandEnvironmentHydrationResult.failure(
              CommandEnvironmentHydrationFailureReason.timeout,
            );
          },
        );

        final environment = await resolver.environment();

        expect(environment, <String, String>{
          'SHELL': '/bin/zsh',
          'PATH': '/usr/bin',
        });
      },
    );
  });

  group('login shell hydration', () {
    test('probes the login shell through the injected runner', () async {
      final runner = _FakeProcessRunner(
        stdout:
            '$shellPathHydrationDelimiter'
            '/opt/homebrew/bin:/usr/bin'
            '$shellPathHydrationDelimiter',
      )..exit.complete(0);

      final result = await hydrateShellPath('/bin/zsh', processRunner: runner);

      expect(result.ok, isTrue);
      expect(result.segments, <String>['/opt/homebrew/bin', '/usr/bin']);
      expect(runner.executable, '/bin/zsh');
      expect(runner.arguments.first, '-ilc');
      expect(runner.arguments.last, contains(shellPathHydrationDelimiter));
    });

    test('reports a spawn error when the shell cannot start', () async {
      final runner = _FakeProcessRunner(
        startError: const ProcessException('/bin/zsh', <String>[]),
      );

      final result = await hydrateShellPath('/bin/zsh', processRunner: runner);

      expect(
        result.failureReason,
        CommandEnvironmentHydrationFailureReason.spawnError,
      );
    });

    test('reports a spawn error raised after the shell started', () async {
      final runner = _FakeProcessRunner();

      final pending = hydrateShellPath('/bin/zsh', processRunner: runner);
      await pumpEventQueue();
      runner.exit.completeError(const ProcessException('/bin/zsh', <String>[]));

      expect(
        (await pending).failureReason,
        CommandEnvironmentHydrationFailureReason.spawnError,
      );
    });

    test('reports an empty PATH when the probe prints no delimiters', () async {
      final runner = _FakeProcessRunner(stdout: 'welcome to zsh')
        ..exit.complete(0);

      final result = await hydrateShellPath('/bin/zsh', processRunner: runner);

      expect(
        result.failureReason,
        CommandEnvironmentHydrationFailureReason.emptyPath,
      );
    });

    test('kills the probe and reports a timeout when the shell hangs', () {
      final runner = _FakeProcessRunner();
      CommandEnvironmentHydrationResult? result;

      fakeAsync((async) {
        unawaited(
          hydrateShellPath(
            '/bin/zsh',
            processRunner: runner,
          ).then((value) => result = value),
        );
        async.elapse(shellPathHydrationTimeout * 2);
        async.flushMicrotasks();
      });

      expect(runner.killCount, 1);
      expect(
        result?.failureReason,
        CommandEnvironmentHydrationFailureReason.timeout,
      );
    });

    test('hydrates requested variables through the injected runner', () async {
      final runner = _FakeProcessRunner(
        stdout:
            '${shellVariableHydrationDelimiter}CCS_DIR=/home/test/.ccs'
            '$shellVariableHydrationDelimiter',
      )..exit.complete(0);

      final values = await hydrateShellVariables('/bin/zsh', <String>[
        'CCS_DIR',
      ], processRunner: runner);

      expect(values, <String, String>{'CCS_DIR': '/home/test/.ccs'});
      expect(runner.arguments.first, '-ilc');
    });

    test('returns no variables when the shell cannot start', () async {
      final runner = _FakeProcessRunner(
        startError: const ProcessException('/bin/zsh', <String>[]),
      );

      expect(
        await hydrateShellVariables('/bin/zsh', <String>[
          'CCS_DIR',
        ], processRunner: runner),
        isEmpty,
      );
    });
  });
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner({this.stdout = '', this.startError});

  final String stdout;
  final Object? startError;
  final Completer<int> exit = Completer<int>();

  String? executable;
  List<String> arguments = const <String>[];
  int killCount = 0;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError('Hydration only starts processes.');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    final failure = startError;
    if (failure != null) {
      throw failure;
    }
    return StartedProcess(
      stdinWrite: (_) {},
      stdout: Stream<List<int>>.value(utf8.encode(stdout)),
      stderr: const Stream<List<int>>.empty(),
      pid: 4242,
      exitCode: exit.future,
      kill: ([dynamic signal]) {
        killCount += 1;
        return true;
      },
    );
  }
}
