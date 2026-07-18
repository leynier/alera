import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
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
        ]);

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
}
