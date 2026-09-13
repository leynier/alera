import 'package:alera_mobile/src/features/workbench/domain/host_absolute_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joins POSIX host roots with forward slashes', () {
    expect(
      hostAbsolutePath(rootPath: '/repo', relativePath: 'lib/main.dart'),
      '/repo/lib/main.dart',
    );
    expect(
      hostAbsolutePath(rootPath: '/repo/', relativePath: 'lib/main.dart'),
      '/repo/lib/main.dart',
    );
  });

  test('joins Windows host roots with backslashes', () {
    expect(
      hostAbsolutePath(rootPath: r'C:\repo', relativePath: 'lib/main.dart'),
      r'C:\repo\lib\main.dart',
    );
    expect(
      hostAbsolutePath(rootPath: r'C:\repo\', relativePath: 'lib/main.dart'),
      r'C:\repo\lib\main.dart',
    );
    expect(
      hostAbsolutePath(
        rootPath: r'\\server\share\repo',
        relativePath: 'docs/readme.md',
      ),
      r'\\server\share\repo\docs\readme.md',
    );
  });

  test('an empty relative path is the root itself', () {
    expect(hostAbsolutePath(rootPath: '/repo', relativePath: ''), '/repo');
  });
}
