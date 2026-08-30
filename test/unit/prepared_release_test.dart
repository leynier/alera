import 'package:flutter_test/flutter_test.dart';

import '../../tool/github/main_ruleset.dart';
import '../../tool/release/prepared_release.dart';
import '../../tool/release/release_plan.dart';

void main() {
  const desktop = PreparedProductRelease(
    shouldRelease: true,
    artifactVersion: '1.2.0',
    releaseVersion: '1.2.0',
    buildNumber: 42,
    tag: 'v1.2.0',
    previousTag: 'v1.1.0',
  );
  const mobile = PreparedProductRelease(
    shouldRelease: true,
    artifactVersion: '0.8.1',
    releaseVersion: '0.8.1',
    buildNumber: 43,
    tag: 'v0.8.1-mobile',
    previousTag: 'v0.8.0-mobile',
  );
  const release = PreparedRelease(
    sourceSha: '1111111111111111111111111111111111111111',
    channel: ReleaseChannel.stable,
    desktop: desktop,
    mobile: mobile,
  );

  group('prepared release', () {
    test('round trips its immutable identity and changed paths', () {
      final decoded = PreparedRelease.fromJson(release.toJson());

      expect(decoded.title, 'release: v1.2.0 v0.8.1-mobile');
      expect(decoded.branchName, 'release/version-v1.2.0-and-v0.8.1-mobile');
      expect(decoded.tags, ['v1.2.0', 'v0.8.1-mobile']);
      expect(decoded.requiredChangedPaths, {
        preparedReleasePath,
        'pubspec.yaml',
        'mobile/pubspec.yaml',
      });
      expect(decoded.expectedChangedPaths, {
        preparedReleasePath,
        'pubspec.yaml',
        'mobile/pubspec.yaml',
        'landing/src/data/releases.json',
      });
      expect(decoded.optionalUnchangedPaths, {
        'landing/src/data/releases.json',
      });
    });

    test('rejects a tag whose channel does not match', () {
      expect(
        () => PreparedRelease(
          sourceSha: release.sourceSha,
          channel: ReleaseChannel.rc,
          desktop: desktop,
          mobile: mobile,
        ).validate(),
        throwsFormatException,
      );
    });

    test('detects a stale plan before publication', () {
      release.validateReplannedOutputs({
        'channel': 'stable',
        'desktop_should_release': 'true',
        'desktop_tag': 'v1.2.0',
        'mobile_should_release': 'true',
        'mobile_tag': 'v0.8.1-mobile',
      });

      expect(
        () => release.validateReplannedOutputs({
          'channel': 'stable',
          'desktop_should_release': 'true',
          'desktop_tag': 'v2.0.0',
          'mobile_should_release': 'true',
          'mobile_tag': 'v0.8.1-mobile',
        }),
        throwsStateError,
      );
    });
  });

  test('main ruleset grants only Mergify bypass', () {
    final ruleset = desiredMainRuleset(
      mergifyAppId: 10562,
      githubActionsAppId: 15368,
    );
    final bypass = ruleset['bypass_actors']! as List<Object?>;
    final rules = ruleset['rules']! as List<Object?>;
    final checks =
        (rules.singleWhere(
              (rule) =>
                  (rule! as Map<String, Object?>)['type'] ==
                  'required_status_checks',
            ) as Map<String, Object?>)['parameters']!
            as Map<String, Object?>;

    expect(bypass, [
      {'actor_id': 10562, 'actor_type': 'Integration', 'bypass_mode': 'always'},
    ]);
    expect(rules.map((rule) => (rule! as Map)['type']), [
      'deletion',
      'non_fast_forward',
      'pull_request',
      'required_status_checks',
    ]);
    expect(checks['required_status_checks'], [
      {'context': 'pr-ready', 'integration_id': 15368},
      {'context': 'queue-ready', 'integration_id': 15368},
    ]);
  });
}
