import 'package:alera_mobile/src/features/updater/application/mobile_update_providers.dart';
import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:alera_mobile/src/features/updater/presentation/mobile_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

final MobileRelease _release = MobileRelease(
  version: const MobileVersion(0, 10, 0),
  tag: 'v0.10.0-mobile',
  apkUrl: Uri.parse(
    'https://github.com/leynier/alera/releases/download/'
    'v0.10.0-mobile/alera-0.10.0-android.apk',
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required MobileRelease? release,
  required List<String> copied,
  required List<(Uri, LaunchMode)> opened,
  bool openResult = true,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        availableMobileUpdateProvider.overrideWith((ref) async => release),
      ],
      child: MaterialApp(
        home: MobileUpdatePrompt(
          copyLink: (link) async => copied.add(link),
          openUrl: (url, {mode = LaunchMode.platformDefault}) async {
            opened.add((url, mode));
            return openResult;
          },
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offers the universal apk when a newer release exists', (
    tester,
  ) async {
    final copied = <String>[];
    final opened = <(Uri, LaunchMode)>[];
    await _pump(tester, release: _release, copied: copied, opened: opened);
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('0.10.0'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(opened, <(Uri, LaunchMode)>[
      (_release.apkUrl, LaunchMode.externalApplication),
    ]);
  });

  testWidgets('copies the apk link without opening it', (tester) async {
    final copied = <String>[];
    final opened = <(Uri, LaunchMode)>[];
    await _pump(tester, release: _release, copied: copied, opened: opened);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();

    expect(copied, <String>[_release.apkUrl.toString()]);
    expect(opened, isEmpty);
    expect(find.text('Download link copied.'), findsOneWidget);
  });

  testWidgets('declining opens nothing and does not ask again', (tester) async {
    final copied = <String>[];
    final opened = <(Uri, LaunchMode)>[];
    await _pump(tester, release: _release, copied: copied, opened: opened);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(opened, isEmpty);
    expect(find.text('Update available'), findsNothing);

    // A rebuild must not re-open the dialog the user just dismissed.
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('stays silent when the app is current', (tester) async {
    final copied = <String>[];
    final opened = <(Uri, LaunchMode)>[];
    await _pump(tester, release: null, copied: copied, opened: opened);
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(copied, isEmpty);
    expect(opened, isEmpty);
  });
}
