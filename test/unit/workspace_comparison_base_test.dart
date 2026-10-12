import 'package:alera/src/features/workbench/domain/workspace_comparison_base.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const branches = [
    'main',
    'origin/main',
    'feature/base',
    'upstream/feature/base',
    'release',
  ];
  test(
    'explicit, open review, source and default bases have ordered priority',
    () {
      String? resolve({String? explicit, String? review, String? source}) =>
          resolveWorkspaceComparisonBase(
            branches: branches,
            remoteNames: ['origin', 'upstream'],
            defaultBranch: 'main',
            explicitBase: explicit,
            openReviewBase: review,
            sourceBranch: source,
          );
      expect(
        resolve(explicit: 'release', review: 'feature/base', source: 'main'),
        'release',
      );
      expect(
        resolve(review: 'feature/base', source: 'release'),
        'upstream/feature/base',
      );
      expect(resolve(review: 'missing', source: 'release'), 'release');
      expect(resolve(source: 'missing'), 'origin/main');
      expect(resolve(explicit: 'main'), 'origin/main');
      expect(resolve(explicit: 'missing'), 'missing');
    },
  );
  test('review base strips actual remote prefixes and preserves local branch paths', () {
    expect(
      shortWorkspaceBranchRef('upstream/feature/base', ['upstream']),
      'feature/base',
    );
    expect(shortWorkspaceBranchRef('feature/base', ['origin']), 'feature/base');
  });
  test('an unborn repository uses the empty-tree comparison', () {
    expect(
      resolveWorkspaceComparisonBase(branches: [], defaultBranch: 'main'),
      isNull,
    );
  });
}
