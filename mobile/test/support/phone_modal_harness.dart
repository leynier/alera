import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the shipped Inter so layout checks measure the app's real glyphs
/// rather than the square test font, which is far wider at large sizes.
Future<void> loadShippedInter() async {
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
}

/// A phone of [size] with a [keyboard] inset and a [homeIndicator] inset,
/// reset when the test ends.
void usePhone(
  WidgetTester tester, {
  required Size size,
  double keyboard = 0,
  double homeIndicator = 0,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = FakeViewPadding(top: 20, bottom: homeIndicator);
  tester.view.viewPadding = FakeViewPadding(top: 20, bottom: homeIndicator);
  addTearDown(tester.view.reset);
}

/// Pumps the app theme at [textScale] with an Open button that runs [open],
/// or with [trigger] in its place, then taps it.
Future<void> openFromPhone(
  WidgetTester tester, {
  Future<void> Function(BuildContext context)? open,
  Widget? trigger,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              trigger ??
              TextButton(
                onPressed: () => open!(context),
                child: const Text('Open'),
              ),
        ),
      ),
    ),
  );
  await tester.tap(
    trigger == null ? find.text('Open') : find.byWidget(trigger),
  );
  await tester.pumpAndSettle();
}

/// The bottom of what the keyboard leaves visible.
double visibleBottom(WidgetTester tester) =>
    tester.view.physicalSize.height - tester.view.viewInsets.bottom;
