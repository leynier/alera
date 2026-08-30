import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'command_terminal_test_doubles.dart';

const String _debUpgradeCommand =
    'sudo apt-get update && sudo apt-get install --only-upgrade alera';

void main() {
  group('UpdateSettingsSection', () {
    testWidgets('offers the upgrade command for a Linux package', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final controller = _FakeUpdateController(
        _state(
          status: .manualDownloadRequired,
          latest: _latest().copyWith(platform: 'linux', installerKind: 'deb'),
          message: 'Update 1.2.3 is available through the package repository.',
        ),
      );
      await _pumpSection(
        tester,
        controller,
        packageInstall: const PackageManagerInstall(
          method: .linuxSystemPackage,
        ),
      );

      expect(find.text(_debUpgradeCommand), findsOneWidget);
      expect(find.text('Installation Guide'), findsOneWidget);
      expect(
        find.text('Download Manually'),
        findsNothing,
        reason: 'a loose .deb is what the package repository replaces',
      );

      await tester.tap(find.byTooltip('Copy Command'));
      await tester.pump();

      expect(copied, <String>[_debUpgradeCommand]);
    });

    testWidgets('runs the upgrade command and offers to restart after', (
      tester,
    ) async {
      final runtime = FakeCommandTerminalRuntime(running: false);
      final controller = _FakeUpdateController(
        _state(
          status: .manualDownloadRequired,
          latest: _latest().copyWith(platform: 'linux', installerKind: 'deb'),
        ),
      );
      await _pumpSection(
        tester,
        controller,
        runtime: runtime,
        packageInstall: const PackageManagerInstall(
          method: .linuxSystemPackage,
        ),
      );

      await tester.tap(find.text('Run Update'));
      await tester.pumpAndSettle();

      expect(find.text('Update Alera'), findsOneWidget);
      expect(runtime.lastTab?.initialCommand, _debUpgradeCommand);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(runtime.closedTabIds, <String>[runtime.lastTab!.id]);
      expect(controller.checkForUpdatesCalls, 0);
      expect(controller.requireRestartCalls, 1);
      expect(find.text('Restart Alera'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Restart Alera'));
      await tester.pump();

      expect(controller.restartAppCalls, 1);
    });

    testWidgets(
      'renders copy, status actions, and progress across update states',
      (tester) async {
        final controller = _FakeUpdateController(_state());
        await _pumpSection(tester, controller);

        expect(find.text('Update status'), findsOneWidget);
        expect(find.text('Check for Updates'), findsOneWidget);

        controller.setState(
          _state(status: .checking, message: 'Checking for updates.'),
        );
        await tester.pump();
        expect(find.text('Checking for updates'), findsOneWidget);
        expect(find.text('Checking'), findsOneWidget);

        controller.setState(
          _state(
            status: .notAvailable,
            message: 'Alera is up to date.',
            currentVersion: '1.0.0',
            currentBuildNumber: '100',
          ),
        );
        await tester.pump();
        expect(find.text('No update available'), findsOneWidget);
        expect(find.text('Current version 1.0.0 (build 100)'), findsOneWidget);
        expect(find.text('Alera is up to date.'), findsOneWidget);

        controller.setState(
          _state(
            status: .manualDownloadRequired,
            latest: _latest(),
            message: 'Manual download required.',
            currentVersion: '1.0.0',
            currentBuildNumber: '100',
          ),
        );
        await tester.pump();
        expect(find.text('Manual update available'), findsOneWidget);
        expect(find.text('Current version 1.0.0 (build 100)'), findsOneWidget);
        expect(find.text('Update version 1.2.3 (build 123)'), findsOneWidget);
        expect(find.text('Download Manually'), findsOneWidget);

        controller.setState(
          _state(
            status: .available,
            latest: _latest(),
            message: 'Ready to install.',
          ),
        );
        await tester.pump();
        expect(find.text('Update available'), findsOneWidget);
        expect(find.text('Install Update'), findsOneWidget);

        controller.setState(
          _state(
            status: .downloading,
            latest: _latest(),
            message: 'Downloading update 1.2.3.',
            progress: 0.4,
          ),
        );
        await tester.pump();
        expect(find.text('Downloading update'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        controller.setState(
          _state(
            status: .applying,
            latest: _latest(),
            message: 'Installing update 1.2.3. Alera will restart.',
            progress: 1,
          ),
        );
        await tester.pump();
        expect(find.text('Installing update'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNull,
        );

        controller.setState(
          _state(
            status: .downloaded,
            latest: _latest(),
            message: 'Update handoff complete.',
            progress: 1,
          ),
        );
        await tester.pump();
        expect(find.text('Restarting Alera'), findsOneWidget);
        expect(find.text('Update handoff complete.'), findsOneWidget);

        controller.setState(
          _state(
            status: .error,
            latest: _latest(),
            message: 'Update installation failed: boom',
          ),
        );
        await tester.pump();
        expect(find.text('Update failed'), findsOneWidget);
        expect(find.text('Update installation failed: boom'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
      },
    );

    testWidgets('dispatches the visible update actions to the controller', (
      tester,
    ) async {
      final controller = _FakeUpdateController(_state());
      await _pumpSection(tester, controller);

      await tester.tap(find.text('Check for Updates'));
      await tester.pump();
      expect(controller.checkForUpdatesCalls, 1);

      controller.setState(
        _state(status: .manualDownloadRequired, latest: _latest()),
      );
      await tester.pump();
      await tester.tap(find.text('Download Manually'));
      await tester.pump();
      expect(controller.openDownloadPageCalls, 1);

      controller.setState(_state(status: .available, latest: _latest()));
      await tester.pump();
      await tester.tap(find.text('Install Update'));
      await tester.pump();
      expect(controller.installLatestCalls, 1);

      controller.setState(_state(status: .error, latest: _latest()));
      await tester.pump();
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(controller.installLatestCalls, 2);
    });
  });
}

Future<void> _pumpSection(
  WidgetTester tester,
  _FakeUpdateController controller, {
  FakeCommandTerminalRuntime? runtime,
  // Stated rather than inherited from wherever the test runner happens to
  // live: which manager owns the installation is what decides whether an
  // upgrade command is offered at all.
  PackageManagerInstall packageInstall = PackageManagerInstall.unmanaged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraUpdateControllerProvider.overrideWith(() => controller),
        packageManagerInstallProvider.overrideWithValue(packageInstall),
        if (runtime != null) terminalRuntimeProvider.overrideWithValue(runtime),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: UpdateSettingsSection()),
      ),
    ),
  );
  await tester.pump();
}

AleraUpdateState _state({
  AleraUpdateStatus status = AleraUpdateStatus.idle,
  AleraUpdateInfo? latest,
  String? message,
  double progress = 0,
  String? currentVersion,
  String? currentBuildNumber,
}) {
  return AleraUpdateState(
    status: status,
    config: _config(),
    latest: latest,
    message: message,
    progress: progress,
    currentVersion: currentVersion,
    currentBuildNumber: currentBuildNumber,
  );
}

AleraUpdateInfo _latest() {
  return AleraUpdateInfo(
    version: '1.2.3',
    shortVersion: 123,
    date: '2026-05-25',
    mandatory: false,
    url: Uri.parse('https://example.com/alera.zip'),
    platform: 'macos',
    changes: const <String>['Improved coverage'],
  );
}

AleraUpdateConfig _config() {
  return AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://example.com/releases'),
    channel: .stable,
    autoInstallEnabled: true,
    signedRelease: true,
  );
}

class _FakeUpdateController(final AleraUpdateState _seed)
    extends AleraUpdateController {
  int checkForUpdatesCalls = 0;
  int installLatestCalls = 0;
  int openDownloadPageCalls = 0;
  int restartAppCalls = 0;
  int requireRestartCalls = 0;

  @override
  AleraUpdateState build() => _seed;

  void setState(AleraUpdateState next) {
    state = next;
  }

  @override
  Future<void> checkForUpdates() async {
    checkForUpdatesCalls += 1;
  }

  @override
  Future<void> installLatest() async {
    installLatestCalls += 1;
  }

  @override
  Future<void> openDownloadPage() async {
    openDownloadPageCalls += 1;
  }

  @override
  void requireRestartAfterManualUpdate() {
    requireRestartCalls += 1;
    state = state.copyWith(status: .restartRequired);
  }

  @override
  Future<void> restartApp() async {
    restartAppCalls += 1;
  }
}
