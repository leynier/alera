import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop presence snapshot', () {
    test('clears the badge when the dock setting is off', () {
      final snapshot = desktopPresenceSnapshot(
        showTrayIcon: true,
        showDockBadge: false,
        showTrayBadge: true,
        pendingReviewCount: 4,
      );
      expect(snapshot.trayVisible, isTrue);
      expect(snapshot.badgeCount, 0);
      expect(snapshot.tooltip, '4 agents need attention');
    });

    test('hides the tray independently of the badge', () {
      final snapshot = desktopPresenceSnapshot(
        showTrayIcon: false,
        showDockBadge: true,
        showTrayBadge: true,
        pendingReviewCount: 1,
      );
      expect(snapshot.trayVisible, isFalse);
      expect(snapshot.badgeCount, 1);
      expect(snapshot.tooltip, '1 agent needs attention');
    });

    test('carries the tray badge apart from the dock badge', () {
      final trayOnly = desktopPresenceSnapshot(
        showTrayIcon: true,
        showDockBadge: false,
        showTrayBadge: true,
        pendingReviewCount: 3,
      );
      expect(trayOnly.badgeCount, 0);
      expect(trayOnly.trayBadgeCount, 3);

      final dockOnly = desktopPresenceSnapshot(
        showTrayIcon: true,
        showDockBadge: true,
        showTrayBadge: false,
        pendingReviewCount: 3,
      );
      expect(dockOnly.badgeCount, 3);
      expect(dockOnly.trayBadgeCount, 0);
    });

    test('a changed tray badge is a different snapshot', () {
      // The coordinator skips an apply when the snapshot compares equal, so a
      // tray-only change has to be visible to ==.
      const base = DesktopPresenceSnapshot(
        trayVisible: true,
        tooltip: 'x',
        badgeCount: 0,
        trayBadgeCount: 1,
      );
      const changed = DesktopPresenceSnapshot(
        trayVisible: true,
        tooltip: 'x',
        badgeCount: 0,
        trayBadgeCount: 2,
      );
      expect(base == changed, isFalse);
      expect(base.hashCode == changed.hashCode, isFalse);
    });

    test('uses the flavor desktop id for Unity launcher entries', () {
      expect(
        linuxLauncherDesktopId(bundleId: kAleraReleaseBundleId),
        'dev.leynier.alera.desktop',
      );
      expect(
        linuxLauncherDesktopId(bundleId: kAleraDevBundleId),
        'dev.leynier.alera.dev.desktop',
      );
    });
  });
}
