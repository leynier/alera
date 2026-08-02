import 'package:alera/src/features/workbench/domain/workspace_file_quick_open.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty query returns deterministic paths', () {
    final matches = rankWorkspaceFileQuickOpenMatches(<String>[
      'lib/zeta.dart',
      'A.dart',
      'a.dart',
    ], '');

    expect(matches.map((match) => match.relativePath), <String>[
      'A.dart',
      'a.dart',
      'lib/zeta.dart',
    ]);
  });

  test('matching is case insensitive', () {
    final matches = rankWorkspaceFileQuickOpenMatches(<String>[
      'lib/README.md',
      'lib/reader.dart',
    ], 'readme');

    expect(matches.map((match) => match.relativePath), <String>[
      'lib/README.md',
    ]);
  });

  test('exact paths outrank prefixes and path-segment matches', () {
    final matches = rankWorkspaceFileQuickOpenMatches(<String>[
      'lib/main.dart',
      'main.dart',
      'lib/maintenance.dart',
      'src/main_test.dart',
    ], 'main.dart');

    expect(matches.map((match) => match.relativePath), <String>[
      'main.dart',
      'lib/main.dart',
      'src/main_test.dart',
      'lib/maintenance.dart',
    ]);
  });

  test('fuzzy subsequence matching finds useful path segments', () {
    final matches = rankWorkspaceFileQuickOpenMatches(<String>[
      'lib/workspace_state.dart',
      'lib/workbench.dart',
      'README.md',
    ], 'wst');

    expect(
      matches.map((match) => match.relativePath),
      contains('lib/workspace_state.dart'),
    );
  });

  test('contains matches are ranked before fuzzy matches', () {
    final matches = rankWorkspaceFileQuickOpenMatches(<String>[
      'lib/terminal.dart',
      'lib/microtasks.dart',
    ], 'minal');

    expect(matches.first.relativePath, 'lib/terminal.dart');
    expect(matches.first.score, greaterThan(1000));
  });

  test('result count is bounded and ties have stable ordering', () {
    final matches = rankWorkspaceFileQuickOpenMatches(
      <String>['src/b.dart', 'src/a.dart', 'src/c.dart'],
      'src',
      limit: 2,
    );

    expect(matches.length, 2);
    expect(matches.map((match) => match.relativePath), <String>[
      'src/a.dart',
      'src/b.dart',
    ]);
  });
}
