import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateSettingsSection', () {
    testWidgets('renders copy, status actions, and progress across update states', (
      tester,
    ) async {
      final controller = _FakeUpdateController(_state());
      await _pumpSection(tester, controller);

      expect(find.text('Update status'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);

      controller.setState(
        _state(
          status: AleraUpdateStatus.checking,
          message: 'Checking for updates.',
        ),
      );
      await tester.pump();
      expect(find.text('Checking for updates'), findsOneWidget);
      expect(find.text('Checking'), findsOneWidget);

      controller.setState(
        _state(
          status: AleraUpdateStatus.notAvailable,
          latest: _latest(),
          message: 'Alera is up to date.',
        ),
      );
      await tester.pump();
      expect(find.text('No update available'), findsOneWidget);
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
      expect(find.text('Manual update available'), findsOneWidget);
      expect(find.text('Download manually'), findsOneWidget);

      controller.setState(
        _state(
          status: AleraUpdateStatus.available,
          latest: _latest(),
          message: 'Ready to install.',
        ),
      );
      await tester.pump();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Download update'), findsOneWidget);

      controller.setState(
        _state(
          status: AleraUpdateStatus.downloading,
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
          status: AleraUpdateStatus.downloaded,
          latest: _latest(),
          message: 'Restart Alera to finish installing.',
          progress: 1,
        ),
      );
      await tester.pump();
      expect(find.text('Restart required'), findsOneWidget);
      expect(find.text('Restart Alera'), findsOneWidget);

      controller.setState(
        _state(
          status: AleraUpdateStatus.error,
          latest: _latest(),
          message: 'Update check failed: boom',
        ),
      );
      await tester.pump();
      expect(find.text('Update check failed'), findsOneWidget);
      expect(find.text('Update check failed: boom'), findsOneWidget);
    });

    testWidgets('dispatches the visible update actions to the controller', (
      tester,
    ) async {
      final controller = _FakeUpdateController(_state());
      await _pumpSection(tester, controller);

      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      expect(controller.checkForUpdatesCalls, 1);

      controller.setState(
        _state(
          status: AleraUpdateStatus.manualDownloadRequired,
          latest: _latest(),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Download manually'));
      await tester.pump();
      expect(controller.openDownloadPageCalls, 1);

      controller.setState(
        _state(status: AleraUpdateStatus.available, latest: _latest()),
      );
      await tester.pump();
      await tester.tap(find.text('Download update'));
      await tester.pump();
      expect(controller.installLatestCalls, 1);

      controller.setState(
        _state(status: AleraUpdateStatus.downloaded, latest: _latest()),
      );
      await tester.pump();
      await tester.tap(find.text('Restart Alera'));
      await tester.pump();
      expect(controller.restartAppCalls, 1);
    });
  });
}

Future<void> _pumpSection(
  WidgetTester tester,
  _FakeUpdateController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [updateControllerProvider.overrideWith(() => controller)],
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
