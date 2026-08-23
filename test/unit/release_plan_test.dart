import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/release_plan.dart';

void main() {
  const desktop = ReleaseProduct.desktop;
  const mobile = ReleaseProduct.mobile;

  group('release tags', () {
    test(
      'parses independent stable and RC patterns and orders semantically',
      () {
        final tags = [
          'v1.9.0',
          'v1.10.0-rc.2',
          'v0.4.0-mobile',
          'v0.5.0-rc.3-mobile',
        ].map(parseReleaseTag).whereType<ReleaseTag>().toList();
        expect(tags, hasLength(4));
        expect(tags[1].core.compareTo(tags[0].core), greaterThan(0));
        expect(tags[2].product, mobile);
        expect(tags[3].rc, 3);
        expect(parseReleaseTag('mobile-v0.4.0'), isNull);
      },
    );
  });

  group('product changes', () {
    test('separates path scopes and bookkeeping', () {
      expect(pathsMatchProduct(mobile, ['mobile/lib/main.dart']), isTrue);
      expect(pathsMatchProduct(desktop, ['mobile/lib/main.dart']), isFalse);
      expect(pathsMatchProduct(desktop, ['landing/index.html']), isFalse);
      expect(pathsMatchProduct(desktop, ['lib/main.dart']), isTrue);
      expect(
        isReleaseBookkeepingSubject('release: v1.2.3 v0.4.0-mobile'),
        isTrue,
      );
      expect(
        isReleaseBookkeepingSubject('release: v1.2.3 v0.4.0-mobile (#123)'),
        isTrue,
      );
    });

    test('uses maximum conventional bump including breaking body', () {
      final changes = [
        const ReleaseChange(
          subject: 'fix: one',
          body: '',
          paths: ['lib/a.dart'],
        ),
        const ReleaseChange(
          subject: 'feat(ui): two',
          body: '',
          paths: ['lib/b.dart'],
        ),
        const ReleaseChange(
          subject: 'refactor: three',
          body: 'BREAKING CHANGE: API changed',
          paths: ['lib/c.dart'],
        ),
        const ReleaseChange(
          subject: 'feat: mobile',
          body: '',
          paths: ['mobile/a.dart'],
        ),
      ];
      expect(classifyChanges(desktop, changes), VersionBump.major);
      expect(classifyChanges(mobile, changes), VersionBump.minor);
    });
  });

  group('version planning', () {
    const desktopFeature = ReleaseChange(
      subject: 'feat: desktop',
      body: '',
      paths: ['lib/main.dart'],
    );
    const mobileFix = ReleaseChange(
      subject: 'fix: mobile',
      body: '',
      paths: ['mobile/lib/main.dart'],
    );

    test('plans independent products', () {
      final tags = [
        'v1.2.0',
        'v0.4.0-mobile',
      ].map(parseReleaseTag).whereType<ReleaseTag>();
      final desktopPlan = planProductRelease(
        product: desktop,
        channel: ReleaseChannel.stable,
        tags: tags,
        stableChanges: [desktopFeature, mobileFix],
        channelChanges: [desktopFeature, mobileFix],
        currentBuildNumber: 8,
        runNumber: 4,
        dryRun: false,
      );
      final mobilePlan = planProductRelease(
        product: mobile,
        channel: ReleaseChannel.stable,
        tags: tags,
        stableChanges: [desktopFeature, mobileFix],
        channelChanges: [desktopFeature, mobileFix],
        currentBuildNumber: 2,
        runNumber: 4,
        dryRun: false,
      );
      expect(desktopPlan.tag, 'v1.3.0');
      expect(mobilePlan.tag, 'v0.4.1-mobile');
      expect(desktopPlan.buildNumber, 9);
      expect(mobilePlan.buildNumber, 4);
    });

    test('increments RC and does not regress below a public RC core', () {
      final tags = [
        'v1.2.0',
        'v2.0.0-rc.1',
        'v2.0.0-rc.3',
      ].map(parseReleaseTag).whereType<ReleaseTag>();
      final plan = planProductRelease(
        product: desktop,
        channel: ReleaseChannel.rc,
        tags: tags,
        stableChanges: [desktopFeature],
        channelChanges: [desktopFeature],
        currentBuildNumber: 1,
        runNumber: 2,
        dryRun: false,
      );
      expect(plan.artifactVersion, '2.0.0');
      expect(plan.releaseVersion, '2.0.0-rc.4');
      expect(plan.previousTag, 'v2.0.0-rc.3');
    });

    test('identical RC is a no-op and dry run suppresses release', () {
      final noOp = planProductRelease(
        product: desktop,
        channel: ReleaseChannel.rc,
        tags: const [],
        stableChanges: [desktopFeature],
        channelChanges: const [],
        currentBuildNumber: 3,
        runNumber: 10,
        dryRun: false,
      );
      expect(noOp.hasChanges, isFalse);
      expect(noOp.shouldRelease, isFalse);
      expect(noOp.buildNumber, 10);

      final dryRun = planProductRelease(
        product: desktop,
        channel: ReleaseChannel.stable,
        tags: const [],
        stableChanges: [desktopFeature],
        channelChanges: [desktopFeature],
        currentBuildNumber: 10,
        runNumber: 2,
        dryRun: true,
      );
      expect(dryRun.hasChanges, isTrue);
      expect(dryRun.shouldRelease, isFalse);
      expect(dryRun.tag, 'v0.2.0');
      expect(dryRun.buildNumber, 11);
    });

    test('starts the first release candidate at rc zero', () {
      final plan = planProductRelease(
        product: mobile,
        channel: ReleaseChannel.rc,
        tags: [parseReleaseTag('v0.4.0-mobile')!],
        stableChanges: [mobileFix],
        channelChanges: [mobileFix],
        currentBuildNumber: 5,
        runNumber: 6,
        dryRun: false,
      );

      expect(plan.tag, 'v0.4.1-rc.0-mobile');
      expect(plan.previousTag, 'v0.4.0-mobile');
    });
  });
}
