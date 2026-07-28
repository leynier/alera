import 'package:alera_mobile/src/features/updater/application/mobile_update_providers.dart';
import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:alera_mobile/src/features/updater/presentation/mobile_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  required List<Uri> opened,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        availableMobileUpdateProvider.overrideWith((ref) async => release),
      ],
      child: MaterialApp(
        home: MobileUpdatePrompt(
          openUrl: (url) async {
            opened.add(url);
            return true;
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
    final opened = <Uri>[];
    await _pump(tester, release: _release, opened: opened);
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsOneWidget);
    expect(find.textContaining('0.10.0'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(opened, <Uri>[_release.apkUrl]);
  });

  testWidgets('declining opens nothing and does not ask again', (tester) async {
    final opened = <Uri>[];
    await _pump(tester, release: _release, opened: opened);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.text('Update Available'), findsNothing);

    // A rebuild must not re-open the dialog the user just dismissed.
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('stays silent when the app is current', (tester) async {
    final opened = <Uri>[];
    await _pump(tester, release: null, opened: opened);
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
    expect(opened, isEmpty);
  });
}
