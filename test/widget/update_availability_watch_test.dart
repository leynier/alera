import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/presentation/update_availability_watch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateAvailabilityWatch', () {
    testWidgets('announces a background find once per version', (tester) async {
      final controller = _FakeUpdateController(_state());
      await _pump(tester, controller);

      expect(find.textContaining('Update 1.2.3'), findsNothing);

      controller.setState(
        _state(
          status: .available,
          latest: _latest('1.2.3'),
          message: 'Update 1.2.3 is ready to install.',
        ),
      );
      await tester.pump();
      expect(find.text('Update 1.2.3 is ready to install.'), findsOneWidget);

      // The recurring check keeps rediscovering the same release, and a toast
      // every fifteen minutes for one the user already saw is noise.
      controller.setState(_state(status: .checking));
      await tester.pump();
      controller.setState(
        _state(
          status: .available,
          latest: _latest('1.2.3'),
          message: 'Update 1.2.3 is ready to install.',
        ),
      );
      await tester.pump();
      expect(find.text('Update 1.2.3 is ready to install.'), findsOneWidget);

      controller.setState(
        _state(
          status: .manualDownloadRequired,
          latest: _latest('1.3.0'),
          message: 'Update 1.3.0 is available for manual download.',
        ),
      );
      await tester.pump();
      expect(
        find.text('Update 1.3.0 is available for manual download.'),
        findsOneWidget,
      );
    });

    testWidgets('stays silent when there is nothing to install', (
      tester,
    ) async {
      final controller = _FakeUpdateController(_state());
      await _pump(tester, controller);

      controller.setState(
        _state(status: .notAvailable, message: 'Alera is up to date.'),
      );
      await tester.pump();
      expect(find.text('Alera is up to date.'), findsNothing);

      controller.setState(
        _state(status: .error, message: 'Update check failed: boom'),
      );
      await tester.pump();
      expect(find.text('Update check failed: boom'), findsNothing);
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeUpdateController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraUpdateControllerProvider.overrideWith(() => controller),
        appForegroundProvider.overrideWithValue(_HiddenForeground()),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(
          body: UpdateAvailabilityWatch(
            child: Stack(children: <Widget>[AleraToastHost()]),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Reports a hidden window so mounting the watch does not start a real check.
class _HiddenForeground implements AppForeground {
  @override
  bool get isForeground => false;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  void dispose() {}
}

AleraUpdateState _state({
  AleraUpdateStatus status = AleraUpdateStatus.idle,
  AleraUpdateInfo? latest,
  String? message,
}) {
  return AleraUpdateState(
    status: status,
    config: AleraUpdateConfig(
      archiveUrl: Uri.parse('https://example.com/app-archive.json'),
      releasePageUrl: Uri.parse('https://example.com/releases'),
      channel: .stable,
      autoInstallEnabled: true,
      signedRelease: true,
    ),
    latest: latest,
    message: message,
    progress: 0,
  );
}

AleraUpdateInfo _latest(String version) {
  return AleraUpdateInfo(
    version: version,
    shortVersion: 123,
    date: '2026-05-25',
    mandatory: false,
    url: Uri.parse('https://example.com/alera.zip'),
    platform: 'macos',
    changes: const <String>[],
  );
}

class _FakeUpdateController(final AleraUpdateState _seed)
    extends AleraUpdateController {
  @override
  AleraUpdateState build() => _seed;

  void setState(AleraUpdateState next) {
    state = next;
  }

  @override
  Future<void> checkForUpdates() async {}
}
