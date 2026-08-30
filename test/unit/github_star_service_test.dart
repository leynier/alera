import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitHubStarService', () {
    test(
      'checkStarred returns true when gh reports the repo as starred',
      () async {
        final runner = _FakeProcessRunner(<Object>[
          const ProcessRunOutput(exitCode: 0, stdout: '', stderr: ''),
        ]);
        final service = GitHubStarService(runner);

        expect(await service.checkStarred(), isTrue);
        expect(runner.calls.single.executable, 'gh');
      },
    );

    test(
      'checkStarred returns false for 404 responses in stderr or stdout',
      () async {
        final runner = _FakeProcessRunner(<Object>[
          const ProcessRunOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'HTTP 404 not found',
          ),
          const ProcessRunOutput(
            exitCode: 1,
            stdout: 'status: 404',
            stderr: '',
          ),
        ]);
        final service = GitHubStarService(runner);

        expect(await service.checkStarred(), isFalse);
        expect(await service.checkStarred(), isFalse);
      },
    );

    test(
      'checkStarred returns null for unexpected failures and exceptions',
      () async {
        final runner = _FakeProcessRunner(<Object>[
          const ProcessRunOutput(exitCode: 1, stdout: '', stderr: 'boom'),
          StateError('gh missing'),
        ]);
        final service = GitHubStarService(runner);

        expect(await service.checkStarred(), isNull);
        expect(await service.checkStarred(), isNull);
      },
    );

    test(
      'star returns true on success and false on failure or exceptions',
      () async {
        final runner = _FakeProcessRunner(<Object>[
          const ProcessRunOutput(exitCode: 0, stdout: '', stderr: ''),
          const ProcessRunOutput(exitCode: 1, stdout: '', stderr: 'boom'),
          StateError('gh missing'),
        ]);
        final service = GitHubStarService(runner);

        expect(await service.star(), isTrue);
        expect(await service.star(), isFalse);
        expect(await service.star(), isFalse);
      },
    );
  });
}

class _FakeProcessRunner(final List<Object> _results) implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(_ProcessCall(executable, List<String>.from(arguments)));
    final next = _results.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    return next as ProcessRunOutput;
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    throw UnimplementedError();
  }
}

class const _ProcessCall(final String executable, final List<String> arguments);
