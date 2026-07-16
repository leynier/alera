import 'package:alera/src/features/workbench/application/repository_browser_opener.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

class _RecordingLauncher implements ExternalUriLauncher {
  _RecordingLauncher({this.error});

  final Object? error;
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    opened.add(uri);
    if (error case final Object error) {
      throw error;
    }
  }
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner({this.exitCode = 0, this.throws = false});

  int exitCode;
  bool throws;
  final List<(String, List<String>)> runs = <(String, List<String>)>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    runs.add((executable, arguments));
    if (throws) {
      throw StateError('no such command');
    }
    return ProcessRunOutput(exitCode: exitCode, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  late FakeGitBackend git;
  late _RecordingLauncher launcher;
  late _FakeProcessRunner process;
  late RepositoryBrowserOpener opener;

  RepositoryBrowserOpener build() => RepositoryBrowserOpener(
    gitBackend: git,
    launcher: launcher,
    processRunner: process,
    platform: WorkspaceFolderPlatform.linux,
  );

  setUp(() {
    git = FakeGitBackend();
    launcher = _RecordingLauncher();
    process = _FakeProcessRunner();
    opener = build();
  });

  test('opens GitHub origin repo home and queries the given path', () async {
    git.remotesByName = <String, String?>{
      'origin': 'git@github.com:leynier/alera.git',
    };
    final outcome = await opener.open(repoPath: '/repo');

    expect(outcome, OpenRepositoryOutcome.opened);
    expect(
      launcher.opened.single.toString(),
      'https://github.com/leynier/alera',
    );
    expect(git.calls.single.method, 'listRemotes');
    expect(git.calls.single.args['path'], '/repo');
  });

  test('opens Azure DevOps repo home', () async {
    git.remotesByName = <String, String?>{
      'origin': 'https://contoso@dev.azure.com/contoso/App/_git/app',
    };
    final outcome = await opener.open(repoPath: '/repo');

    expect(outcome, OpenRepositoryOutcome.opened);
    expect(
      launcher.opened.single.toString(),
      'https://dev.azure.com/contoso/App/_git/app',
    );
  });

  test('prefers origin over other remotes', () async {
    git.remotesByName = <String, String?>{
      'fork': 'git@github.com:fork/alera.git',
      'origin': 'git@github.com:leynier/alera.git',
    };
    await opener.open(repoPath: '/repo');

    expect(
      launcher.opened.single.toString(),
      'https://github.com/leynier/alera',
    );
  });

  test('no remote -> noRemote and nothing is launched', () async {
    git.remotesByName = <String, String?>{};
    final outcome = await opener.open(repoPath: '/repo');

    expect(outcome, OpenRepositoryOutcome.noRemote);
    expect(launcher.opened, isEmpty);
  });

  test('listRemotes failure -> noRemote', () async {
    git.listRemotesFails = true;
    expect(
      await opener.open(repoPath: '/repo'),
      OpenRepositoryOutcome.noRemote,
    );
    expect(launcher.opened, isEmpty);
  });

  test('unsupported host -> undetectable', () async {
    git.remotesByName = <String, String?>{
      'origin': 'git@gitlab.com:team/repo.git',
    };
    expect(
      await opener.open(repoPath: '/repo'),
      OpenRepositoryOutcome.undetectable,
    );
    expect(launcher.opened, isEmpty);
  });

  test('launcher failure falls back to the native open command', () async {
    launcher = _RecordingLauncher(error: StateError('boom'));
    process = _FakeProcessRunner(exitCode: 0);
    opener = build();
    git.remotesByName = <String, String?>{
      'origin': 'git@github.com:leynier/alera.git',
    };

    final outcome = await opener.open(repoPath: '/repo');

    expect(outcome, OpenRepositoryOutcome.opened);
    expect(process.runs, isNotEmpty);
    expect(process.runs.first.$1, 'xdg-open');
    expect(process.runs.first.$2.single, 'https://github.com/leynier/alera');
  });

  test('launcher and native failure -> openFailed', () async {
    launcher = _RecordingLauncher(error: StateError('boom'));
    process = _FakeProcessRunner(exitCode: 1, throws: true);
    opener = build();
    git.remotesByName = <String, String?>{
      'origin': 'git@github.com:leynier/alera.git',
    };

    expect(
      await opener.open(repoPath: '/repo'),
      OpenRepositoryOutcome.openFailed,
    );
  });

  test('override forces GitHub interpretation on a non-github host', () async {
    git.remotesByName = <String, String?>{
      'origin': 'git@git.acme.inc:team/service.git',
    };
    final outcome = await opener.open(
      repoPath: '/repo',
      override: GitHostingProvider.github,
    );

    expect(outcome, OpenRepositoryOutcome.opened);
    expect(
      launcher.opened.single.toString(),
      'https://git.acme.inc/team/service',
    );
  });
}
