import 'package:alera/src/features/pull_requests/application/base_branch_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortBranchName', () {
    test('strips a single remote prefix', () {
      expect(shortBranchName('origin/main'), 'main');
      expect(shortBranchName('origin/feature/foo'), 'feature/foo');
    });

    test('leaves short names unchanged', () {
      expect(shortBranchName('main'), 'main');
      expect(shortBranchName('  main  '), 'main');
    });
  });

  group('normalizeBaseBranches', () {
    test('deduplicates local and remote tracking names', () {
      expect(
        normalizeBaseBranches(<String>[
          'main',
          'origin/main',
          'feature',
          'origin/feature',
          'develop',
        ]),
        <String>['develop', 'feature', 'main'],
      );
    });

    test('skips empty names', () {
      expect(normalizeBaseBranches(<String>['', '  ', 'main']), <String>[
        'main',
      ]);
    });
  });

  group('pickDefaultBaseBranch', () {
    test('prefers preferred when present', () {
      expect(
        pickDefaultBaseBranch(
          <String>['develop', 'main', 'master'],
          preferred: 'origin/develop',
        ),
        'develop',
      );
    });

    test('falls back to main then master', () {
      expect(
        pickDefaultBaseBranch(<String>['feature', 'master', 'main']),
        'main',
      );
      expect(pickDefaultBaseBranch(<String>['feature', 'master']), 'master');
    });

    test('falls back to first branch then main', () {
      expect(pickDefaultBaseBranch(<String>['develop', 'feature']), 'develop');
      expect(pickDefaultBaseBranch(const <String>[]), 'main');
      expect(
        pickDefaultBaseBranch(const <String>[], preferred: 'origin/release'),
        'release',
      );
    });
  });
}
