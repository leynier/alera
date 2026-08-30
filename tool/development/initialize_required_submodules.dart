import 'dart:convert';
import 'dart:io';

const _requiredSubmodules = <String>[
  'third_party/xterm',
  'third_party/dart_terminal',
];

Future<void> main(List<String> arguments) async {
  final repoRoot = _parseRepoRoot(arguments);
  final initializer = _SubmoduleInitializer(repoRoot);

  try {
    await initializer.run();
  } on _CommandFailure catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

Directory _parseRepoRoot(List<String> arguments) {
  if (arguments.isEmpty) {
    return Directory.current.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--repo-root') {
    return Directory(arguments.last).absolute;
  }
  throw const FormatException(
    'Usage: dart tool/development/initialize_required_submodules.dart '
    '[--repo-root <path>]',
  );
}

final class _SubmoduleInitializer(final Directory repoRoot) {
  Future<void> run() async {
    if (!await Directory(_join(repoRoot.path, '.git')).exists() &&
        !await File(_join(repoRoot.path, '.git')).exists()) {
      throw FileSystemException(
        'Repository metadata was not found. Run this command from the Alera '
        'checkout.',
        repoRoot.path,
      );
    }

    await _git(const <String>['submodule', 'sync', '--recursive']);
    for (final path in _requiredSubmodules) {
      await _checkoutSubmodule(parent: repoRoot, relativePath: path);
    }
    stdout.writeln('Required Alera submodules are ready.');
  }

  Future<void> _checkoutSubmodule({
    required Directory parent,
    required String relativePath,
  }) async {
    final expectedCommit = (await _git(<String>[
      'rev-parse',
      'HEAD:$relativePath',
    ], workingDirectory: parent)).stdout.trim();
    final directory = Directory(_join(parent.path, relativePath));

    await _git(<String>[
      'submodule',
      'sync',
      '--',
      relativePath,
    ], workingDirectory: parent);
    await _git(<String>[
      'submodule',
      'init',
      '--',
      relativePath,
    ], workingDirectory: parent);

    if (await _isGitCheckout(directory)) {
      await _refuseDirtyCheckout(directory, expectedCommit);
    }

    final update = await _git(
      <String>['submodule', 'update', '--init', '--', relativePath],
      workingDirectory: parent,
      allowFailure: true,
    );
    if (update.exitCode != 0) {
      if (!await _isGitCheckout(directory)) {
        throw _CommandFailure(
          'Git could not initialize $relativePath.\n${update.stderr.trim()}',
        );
      }
      stdout.writeln(
        'Fetching missing pinned commit $expectedCommit for $relativePath...',
      );
      await _git(<String>[
        'fetch',
        '--no-tags',
        'origin',
        expectedCommit,
      ], workingDirectory: directory);
      await _git(<String>[
        'checkout',
        '--detach',
        expectedCommit,
      ], workingDirectory: directory);
    }

    final actualCommit = (await _git(const <String>[
      'rev-parse',
      'HEAD',
    ], workingDirectory: directory)).stdout.trim();
    if (actualCommit != expectedCommit) {
      throw _CommandFailure(
        '$relativePath is at $actualCommit instead of $expectedCommit.',
      );
    }

    for (final nestedPath in await _nestedSubmodulePaths(directory)) {
      await _checkoutSubmodule(parent: directory, relativePath: nestedPath);
    }
  }

  Future<void> _refuseDirtyCheckout(
    Directory directory,
    String expectedCommit,
  ) async {
    final currentCommit = await _git(
      const <String>['rev-parse', 'HEAD'],
      workingDirectory: directory,
      allowFailure: true,
    );
    if (currentCommit.exitCode == 0 &&
        currentCommit.stdout.trim() == expectedCommit) {
      return;
    }
    final status = await _git(const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], workingDirectory: directory);
    if (status.stdout.trim().isNotEmpty) {
      throw _CommandFailure(
        'Refusing to move ${directory.path} to $expectedCommit because the '
        'submodule contains local changes. Commit, stash, or remove those '
        'changes first.',
      );
    }
  }

  Future<List<String>> _nestedSubmodulePaths(Directory directory) async {
    final modules = File(_join(directory.path, '.gitmodules'));
    if (!await modules.exists()) {
      return const <String>[];
    }
    final result = await _git(
      const <String>[
        'config',
        '--file',
        '.gitmodules',
        '--get-regexp',
        r'^submodule\..*\.path$',
      ],
      workingDirectory: directory,
      allowFailure: true,
    );
    if (result.exitCode == 1 && result.stdout.trim().isEmpty) {
      return const <String>[];
    }
    if (result.exitCode != 0) {
      throw _CommandFailure(
        'Could not read nested submodules in ${directory.path}.\n'
        '${result.stderr.trim()}',
      );
    }
    return const LineSplitter()
        .convert(result.stdout)
        .map((line) => line.trim().split(RegExp(r'\s+')).last)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> _isGitCheckout(Directory directory) async {
    if (!await directory.exists()) {
      return false;
    }
    final result = await _git(
      const <String>['rev-parse', '--git-dir'],
      workingDirectory: directory,
      allowFailure: true,
    );
    return result.exitCode == 0;
  }

  Future<_CommandResult> _git(
    List<String> arguments, {
    Directory? workingDirectory,
    bool allowFailure = false,
  }) async {
    final cwd = workingDirectory ?? repoRoot;
    stdout.writeln('${cwd.path}> git ${arguments.map(_quoteForLog).join(' ')}');
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: cwd.path,
      runInShell: Platform.isWindows,
    );
    final commandResult = _CommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
    if (!allowFailure && commandResult.exitCode != 0) {
      throw _CommandFailure(
        'Git failed in ${cwd.path}: git ${arguments.join(' ')}\n'
        '${commandResult.stderr.trim()}',
      );
    }
    return commandResult;
  }
}

final class const _CommandResult({
  required final int exitCode,
  required final String stdout,
  required final String stderr,
});

final class const _CommandFailure(final String message) implements Exception;

String _join(String first, String second) {
  final separator = Platform.pathSeparator;
  return '${first.replaceAll(RegExp(r'[/\\]+$'), '')}$separator'
      '${second.replaceAll(RegExp(r'^[/\\]+'), '')}';
}

String _quoteForLog(String value) {
  return value.contains(RegExp(r'\s')) ? '"$value"' : value;
}
