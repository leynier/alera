import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/infra/github_cli_failures.dart';
import 'package:alera/src/features/pull_requests/infra/github_merge_methods.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapGitHubRepoAllowedMergeMethods', () {
    test('returns null when GitHub omits the flags', () {
      expect(
        mapGitHubRepoAllowedMergeMethods(const <String, Object?>{}),
        isNull,
      );
    });

    test('returns null when any merge flag is missing', () {
      expect(
        mapGitHubRepoAllowedMergeMethods(const <String, Object?>{
          'squashMergeAllowed': true,
          'rebaseMergeAllowed': true,
        }),
        isNull,
      );
    });

    test('returns null when any merge flag is not a boolean', () {
      expect(
        mapGitHubRepoAllowedMergeMethods(const <String, Object?>{
          'mergeCommitAllowed': 'false',
          'squashMergeAllowed': true,
          'rebaseMergeAllowed': true,
        }),
        isNull,
      );
    });

    test('returns an empty list when every method is disabled', () {
      expect(
        mapGitHubRepoAllowedMergeMethods(const <String, Object?>{
          'mergeCommitAllowed': false,
          'squashMergeAllowed': false,
          'rebaseMergeAllowed': false,
        }),
        isEmpty,
      );
    });

    test('drops merge commits when the repository forbids them', () {
      expect(
        mapGitHubRepoAllowedMergeMethods(const <String, Object?>{
          'mergeCommitAllowed': false,
          'squashMergeAllowed': true,
          'rebaseMergeAllowed': true,
        }),
        <ReviewMergeMethod>[ReviewMergeMethod.squash, ReviewMergeMethod.rebase],
      );
    });

    test('returns squash only when that is the sole allowed method', () {
      expect(
        mapGitHubRepoAllowedMergeMethods(const <String, Object?>{
          'mergeCommitAllowed': false,
          'squashMergeAllowed': true,
          'rebaseMergeAllowed': false,
        }),
        <ReviewMergeMethod>[ReviewMergeMethod.squash],
      );
    });
  });

  group('mapGitHubRulesetAllowedMergeMethods', () {
    test('returns null when no rule constrains merge methods', () {
      expect(
        mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{'type': 'required_status_checks'},
        ]),
        isNull,
      );
    });

    test('reads allowed_merge_methods from a pull_request rule', () {
      expect(
        mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{
            'type': 'pull_request',
            'parameters': <String, Object?>{
              'allowed_merge_methods': <String>['squash'],
            },
          },
        ]),
        <ReviewMergeMethod>{ReviewMergeMethod.squash},
      );
    });

    test('intersects overlapping ruleset constraints', () {
      expect(
        mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{
            'type': 'pull_request',
            'parameters': <String, Object?>{
              'allowed_merge_methods': <String>['merge', 'squash'],
            },
          },
          <String, Object?>{
            'type': 'merge_method',
            'parameters': <String, Object?>{
              'allowed_merge_methods': <String>['squash', 'rebase'],
            },
          },
        ]),
        <ReviewMergeMethod>{ReviewMergeMethod.squash},
      );
    });

    test('unwraps paginated slurp pages', () {
      expect(
        mapGitHubRulesetAllowedMergeMethods(<Object>[
          <Object>[
            <String, Object?>{
              'type': 'pull_request',
              'parameters': <String, Object?>{
                'allowed_merge_methods': <String>['rebase'],
              },
            },
          ],
        ]),
        <ReviewMergeMethod>{ReviewMergeMethod.rebase},
      );
    });

    test('intersects disjoint constraints to an empty set', () {
      expect(
        mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{
            'type': 'pull_request',
            'parameters': <String, Object?>{
              'allowed_merge_methods': <String>['squash'],
            },
          },
          <String, Object?>{
            'type': 'merge_method',
            'parameters': <String, Object?>{
              'allowed_merge_methods': <String>['rebase'],
            },
          },
        ]),
        isEmpty,
      );
    });

    test('treats an empty allowed list as a declared empty constraint', () {
      expect(
        mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{
            'type': 'pull_request',
            'parameters': <String, Object?>{
              'allowed_merge_methods': <String>[],
            },
          },
        ]),
        isEmpty,
      );
    });

    test(
      'treats unrecognized allowed methods as a declared empty constraint',
      () {
        expect(
          mapGitHubRulesetAllowedMergeMethods(<Object>[
            <String, Object?>{
              'type': 'pull_request',
              'parameters': <String, Object?>{
                'allowed_merge_methods': <String>['fast-forward'],
              },
            },
          ]),
          isEmpty,
        );
      },
    );

    test('rejects a non-list allowed_merge_methods value', () {
      expect(
        () => mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{
            'type': 'pull_request',
            'parameters': <String, Object?>{'allowed_merge_methods': 'squash'},
          },
        ]),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });

    test('rejects a pull_request rule with no allowed_merge_methods', () {
      expect(
        () => mapGitHubRulesetAllowedMergeMethods(<Object>[
          <String, Object?>{
            'type': 'pull_request',
            'parameters': <String, Object?>{},
          },
        ]),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });

    test('rejects a non-array rules payload', () {
      expect(
        () => mapGitHubRulesetAllowedMergeMethods('not-json-array'),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });
  });

  group('preferredReviewMergeMethod', () {
    test('prefers provider default when the forge exposes it', () {
      expect(
        preferredReviewMergeMethod(const <ReviewMergeMethod>[
          ReviewMergeMethod.squash,
          ReviewMergeMethod.providerDefault,
        ]),
        ReviewMergeMethod.providerDefault,
      );
    });

    test('uses the first remaining method after merge commits are dropped', () {
      expect(
        preferredReviewMergeMethod(const <ReviewMergeMethod>[
          ReviewMergeMethod.squash,
          ReviewMergeMethod.rebase,
        ]),
        ReviewMergeMethod.squash,
      );
    });
  });

  group('mapGitHubDisallowedMergeMethodMessage', () {
    test('rewrites the GraphQL merge-commit rejection', () {
      expect(
        mapGitHubDisallowedMergeMethodMessage(
          'GraphQL: Merge commits are not allowed on this repository. '
          '(mergePullRequest)',
        ),
        'Merge commits are not allowed on this repository. Use squash '
        'and merge or rebase and merge instead.',
      );
    });

    test('leaves unrelated stderr unclassified', () {
      expect(
        mapGitHubDisallowedMergeMethodMessage('pull request is not mergeable'),
        isNull,
      );
    });
  });
}
