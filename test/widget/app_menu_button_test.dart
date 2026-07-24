import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraAppMenuButton', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      testWidgets('shows the in-window menu on $platform', (tester) async {
        await _withPlatform(platform, () async {
          await _pumpButton(tester);

          await tester.tap(find.byTooltip('Application Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Settings'), findsOneWidget);
          expect(find.text('Check for Updates'), findsOneWidget);
          expect(find.text('Undo'), findsOneWidget);
          expect(find.text('Cut'), findsOneWidget);
          expect(find.text('About $kAleraAppName'), findsOneWidget);
          expect(find.text('Exit'), findsOneWidget);
        });
      });
    }

    testWidgets('stays out of the window on macOS', (tester) async {
      await _withPlatform(TargetPlatform.macOS, () async {
        await _pumpButton(tester);

        expect(find.byTooltip('Application Menu'), findsNothing);
      });
    });

    testWidgets('keeps edit commands targeted at the focused field', (
      tester,
    ) async {
      await _withPlatform(TargetPlatform.linux, () async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await _pumpButton(tester, controller: controller);

        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'hello');
        await tester.tap(find.byTooltip('Application Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
      });
    });
  });
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

Future<void> _pumpButton(
  WidgetTester tester, {
  TextEditingController? controller,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Row(
            children: <Widget>[
              if (controller != null)
                Expanded(child: TextField(controller: controller)),
              const AleraAppMenuButton(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
