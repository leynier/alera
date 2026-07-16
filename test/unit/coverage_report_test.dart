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
}
