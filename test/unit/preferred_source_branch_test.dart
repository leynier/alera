import 'package:alera/src/features/projects/domain/preferred_source_branch.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickDefaultSourceBranch', () {
    test('returns null when no branches are listed', () {
      expect(pickDefaultSourceBranch(const <String>[]), isNull);
      expect(
        pickDefaultSourceBranch(const <String>[], preferred: 'develop'),
        isNull,
      );
    });

    test('selects the project default when it exists', () {
      expect(
        pickDefaultSourceBranch(const <String>[
          'main',
          'develop',
        ], preferred: 'develop'),
        'develop',
      );
    });

    test('selects origin twin of the project default', () {
      expect(
        pickDefaultSourceBranch(const <String>[
          'main',
          'origin/develop',
        ], preferred: 'develop'),
        'origin/develop',
      );
      expect(
        pickDefaultSourceBranch(const <String>[
          'main',
          'develop',
        ], preferred: 'origin/develop'),
        'develop',
      );
    });

    test('keeps a bare origin/ preferred name that exists', () {
      expect(
        pickDefaultSourceBranch(const <String>[
          'origin/',
          'main',
        ], preferred: 'origin/'),
        'origin/',
      );
      expect(
        pickDefaultSourceBranch(const <String>['main'], preferred: 'origin/'),
        'main',
      );
    });

    test('falls back to main then master then the first branch', () {
      expect(
        pickDefaultSourceBranch(const <String>['develop', 'main']),
        'main',
      );
      expect(
        pickDefaultSourceBranch(const <String>['feature', 'origin/main']),
        'origin/main',
      );
      expect(
        pickDefaultSourceBranch(const <String>['release', 'master']),
        'master',
      );
      expect(
        pickDefaultSourceBranch(const <String>['hotfix', 'origin/master']),
        'origin/master',
      );
      expect(
        pickDefaultSourceBranch(const <String>['release/one']),
        'release/one',
      );
    });

    test('ignores a blank preferred value', () {
      expect(
        pickDefaultSourceBranch(const <String>[
          'develop',
          'main',
        ], preferred: '  '),
        'main',
      );
    });
  });

  group('preferredSourceBranchCandidates', () {
    test('returns nothing for blank input', () {
      expect(preferredSourceBranchCandidates(null), isEmpty);
      expect(preferredSourceBranchCandidates(''), isEmpty);
      expect(preferredSourceBranchCandidates('  '), isEmpty);
    });
  });

  group('NewWorkspaceConfig.preferredSourceBranch', () {
    test('trims a configured branch and treats blanks as unset', () {
      expect(
        const NewWorkspaceConfig(sourceBranch: ' develop ')
            .preferredSourceBranch,
        'develop',
      );
      expect(const NewWorkspaceConfig().preferredSourceBranch, isNull);
      expect(
        const NewWorkspaceConfig(sourceBranch: '  ').preferredSourceBranch,
        isNull,
      );
      expect(
        const NewWorkspaceConfig(sourceBranch: 'develop').isEmpty,
        isFalse,
      );
    });
  });
}
