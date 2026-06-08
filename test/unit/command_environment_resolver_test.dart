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
