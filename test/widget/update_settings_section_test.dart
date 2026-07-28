import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
          status: AleraUpdateStatus.manualDownloadRequired,
          latest: _latest().copyWith(platform: 'linux', installerKind: 'deb'),
          message: 'Update 1.2.3 is available through the package repository.',
        ),
      );
      await _pumpSection(tester, controller);

      expect(find.text(_debUpgradeCommand), findsOneWidget);
      expect(find.text('Installation Guide'), findsOneWidget);
      expect(
        find.text('Download Manually'),
        findsNothing,
        reason: 'a loose .deb is what the package repository replaces',
      );

      await tester.tap(find.text('Copy Command'));
      await tester.pump();

      expect(copied, <String>[_debUpgradeCommand]);
      expect(find.text('Command Copied'), findsOneWidget);
    });

    testWidgets(
      'renders copy, status actions, and progress across update states',
      (tester) async {
        final controller = _FakeUpdateController(_state());
        await _pumpSection(tester, controller);

        expect(find.text('Update Status'), findsOneWidget);
        expect(find.text('Check for Updates'), findsOneWidget);

        controller.setState(
          _state(
            status: AleraUpdateStatus.checking,
            message: 'Checking for updates.',
          ),
        );
        await tester.pump();
        expect(find.text('Checking for Updates'), findsOneWidget);
        expect(find.text('Checking'), findsOneWidget);

        controller.setState(
          _state(
            status: AleraUpdateStatus.notAvailable,
            latest: _latest(),
            message: 'Alera is up to date.',
          ),
        );
        await tester.pump();
        expect(find.text('No Update Available'), findsOneWidget);
        expect(find.text('Version 1.2.3 - Build 123'), findsOneWidget);
        expect(find.text('Alera is up to date.'), findsOneWidget);

        controller.setState(
          _state(
            status: AleraUpdateStatus.manualDownloadRequired,
            latest: _latest(),
            message: 'Manual download required.',
          ),
        );
        await tester.pump();
        expect(find.text('Manual Update Available'), findsOneWidget);
        expect(find.text('Download Manually'), findsOneWidget);

        controller.setState(
          _state(
            status: AleraUpdateStatus.available,
            latest: _latest(),
            message: 'Ready to install.',
          ),
        );
        await tester.pump();
        expect(find.text('Update Available'), findsOneWidget);
        expect(find.text('Install Update'), findsOneWidget);

        controller.setState(
          _state(
            status: AleraUpdateStatus.downloading,
            latest: _latest(),
            message: 'Downloading update 1.2.3.',
            progress: 0.4,
          ),
        );
        await tester.pump();
        expect(find.text('Downloading Update'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        controller.setState(
          _state(
            status: AleraUpdateStatus.applying,
            latest: _latest(),
            message: 'Installing update 1.2.3. Alera will restart.',
            progress: 1,
          ),
        );
        await tester.pump();
        expect(find.text('Installing Update'), findsOneWidget);
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
            status: AleraUpdateStatus.downloaded,
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
            status: AleraUpdateStatus.error,
            latest: _latest(),
            message: 'Update installation failed: boom',
          ),
        );
        await tester.pump();
        expect(find.text('Update Failed'), findsOneWidget);
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
        _state(
          status: AleraUpdateStatus.manualDownloadRequired,
          latest: _latest(),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Download Manually'));
      await tester.pump();
      expect(controller.openDownloadPageCalls, 1);

      controller.setState(
        _state(status: AleraUpdateStatus.available, latest: _latest()),
      );
      await tester.pump();
      await tester.tap(find.text('Install Update'));
      await tester.pump();
      expect(controller.installLatestCalls, 1);

      controller.setState(
        _state(status: AleraUpdateStatus.error, latest: _latest()),
      );
      await tester.pump();
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(controller.installLatestCalls, 2);
    });
  });
}

Future<void> _pumpSection(
  WidgetTester tester,
  _FakeUpdateController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [aleraUpdateControllerProvider.overrideWith(() => controller)],
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
}) {
  return AleraUpdateState(
    status: status,
    config: _config(),
    latest: latest,
    message: message,
    progress: progress,
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
    channel: AleraUpdateChannel.stable,
    autoInstallEnabled: true,
    signedRelease: true,
  );
}

class _FakeUpdateController extends AleraUpdateController {
  _FakeUpdateController(this._seed);

  final AleraUpdateState _seed;

  int checkForUpdatesCalls = 0;
  int installLatestCalls = 0;
  int openDownloadPageCalls = 0;
  int restartAppCalls = 0;

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
  Future<void> restartApp() async {
    restartAppCalls += 1;
  }
}
