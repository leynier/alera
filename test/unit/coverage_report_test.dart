import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coverage report gates maintained domain sources only', () async {
    final directory = await Directory.systemTemp.createTemp(
      'alera-coverage-report-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final lcov = File('${directory.path}/lcov.info')
      ..writeAsStringSync('''
SF:lib/src/features/projects/domain/project.dart
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
SF:lib/src/features/projects/domain/project.mapper.dart
DA:1,0
LF:1
LH:0
end_of_record
SF:lib/src/features/projects/application/project_service.dart
DA:1,0
LF:1
LH:0
end_of_record
SF:lib/src/features/projects/presentation/projects_view.dart
DA:1,0
LF:1
LH:0
end_of_record
SF:lib/src/rust/api/git.dart
DA:1,0
LF:1
LH:0
end_of_record
''');

    final result = await Process.run('dart', <String>[
      'tool/quality/coverage_report.dart',
      '--input',
      lcov.path,
      '--min-lines',
      '100',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stdout, contains('domain lines: 100.00% (2/2)'));
    expect(
      result.stdout,
      contains('lib/src/features/projects/domain/project.dart'),
    );
    expect(result.stdout, isNot(contains('project_service.dart')));
    expect(result.stdout, isNot(contains('projects_view.dart')));
    expect(result.stdout, isNot(contains('project.mapper.dart')));
    expect(result.stdout, isNot(contains('lib/src/rust/api/git.dart')));
  });

  test('merges the same file across shards without double counting', () async {
    final directory = await _tempDirectory();
    final first = _writeLcov(directory, 'shard-0.info', '''
SF:lib/src/features/projects/domain/project.dart
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
''');
    final second = _writeLcov(directory, 'shard-1.info', '''
SF:lib/src/features/projects/domain/project.dart
DA:1,0
DA:2,3
LF:2
LH:1
end_of_record
''');

    final result = await _runReport(<String>[
      '--input',
      first.path,
      '--input',
      second.path,
      '--min-lines',
      '100',
    ]);

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stdout, contains('domain lines: 100.00% (2/2)'));
  });

  test('unions files that only one shard loaded', () async {
    final directory = await _tempDirectory();
    _writeLcov(directory, 'shard-0.info', '''
SF:lib/src/features/projects/domain/project.dart
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
''');
    _writeLcov(directory, 'shard-1.info', '''
SF:lib/src/features/workspaces/domain/workspace.dart
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
''');

    final result = await _runReport(<String>[
      '--input-dir',
      directory.path,
      '--expect-inputs',
      '2',
      '--min-lines',
      '100',
    ]);

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stdout, contains('domain lines: 100.00% (4/4)'));
    expect(result.stdout, contains('projects/domain/project.dart'));
    expect(result.stdout, contains('workspaces/domain/workspace.dart'));
  });

  test('still fails when the merged result leaves a line uncovered', () async {
    final directory = await _tempDirectory();
    final first = _writeLcov(directory, 'shard-0.info', '''
SF:lib/src/features/projects/domain/project.dart
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
''');
    final second = _writeLcov(directory, 'shard-1.info', '''
SF:lib/src/features/projects/domain/project.dart
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
''');

    final result = await _runReport(<String>[
      '--input',
      first.path,
      '--input',
      second.path,
      '--min-lines',
      '100',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('is below'));
  });

  // Without this guard a lost shard artifact reads as zero found lines, which
  // the totals treat as 100% and the gate passes silently.
  test('fails instead of passing vacuously when no records match', () async {
    final directory = await _tempDirectory();
    final lcov = _writeLcov(directory, 'empty.info', '''
SF:lib/src/features/projects/presentation/projects_view.dart
DA:1,0
LF:1
LH:0
end_of_record
''');

    final result = await _runReport(<String>[
      '--input',
      lcov.path,
      '--min-lines',
      '100',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('No maintained domain coverage records'));
  });

  test('fails when fewer inputs than expected are present', () async {
    final directory = await _tempDirectory();
    _writeLcov(directory, 'shard-0.info', '''
SF:lib/src/features/projects/domain/project.dart
DA:1,1
LF:1
LH:1
end_of_record
''');
    _writeLcov(directory, 'notes.txt', 'ignored');

    final result = await _runReport(<String>[
      '--input-dir',
      directory.path,
      '--expect-inputs',
      '4',
      '--min-lines',
      '100',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Expected 4 coverage inputs but found 1'));
  });
}

Future<Directory> _tempDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'alera-coverage-report-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

File _writeLcov(Directory directory, String name, String contents) =>
    File('${directory.path}/$name')..writeAsStringSync(contents);

Future<ProcessResult> _runReport(List<String> args) => Process.run(
  'dart',
  <String>['tool/quality/coverage_report.dart', ...args],
  workingDirectory: Directory.current.path,
);
