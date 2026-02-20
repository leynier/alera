import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

class ProjectService {
  ProjectService(this._processRunner);

  final ProcessRunner _processRunner;

  Future<bool> isGitRepository(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return false;
    }

    final result = await _processRunner.run(
      'git',
      <String>['rev-parse', '--is-inside-work-tree'],
      workingDirectory: path,
    );

    return result.exitCode == 0 && result.stdout.trim() == 'true';
  }
}
