import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/markdown/alera_code_block.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAleraDarkTheme(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  testWidgets('shows the language and copies the code', (tester) async {
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

    await tester.pumpWidget(
      _app(const AleraCodeBlock(code: 'void main() {}', language: 'dart')),
    );

    expect(find.text('dart'), findsOneWidget);
    expect(find.text('void main() {}'), findsOneWidget);
    expect(find.byIcon(AleraIcons.copy), findsOneWidget);

    await tester.tap(find.byTooltip('Copy Code'));
    await tester.pump();

    expect(copied, <String>['void main() {}']);
    expect(find.byIcon(AleraIcons.check), findsOneWidget);
    expect(find.byTooltip('Copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(AleraIcons.check), findsNothing);
    expect(find.byTooltip('Copy Code'), findsOneWidget);
  });

  testWidgets('reveals Copy only while the block is hovered', (tester) async {
    await tester.pumpWidget(
      _app(const AleraCodeBlock(code: 'cargo test', language: 'sh')),
    );
    double copyOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(AleraIconButton),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    expect(copyOpacity(), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('cargo test')));
    await tester.pumpAndSettle();
    expect(copyOpacity(), 1);

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(copyOpacity(), 0);
  });

  testWidgets('omits the header without a language or copy action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AleraCodeBlock(code: 'plain output', showCopy: false)),
    );

    expect(find.text('plain output'), findsOneWidget);
    expect(find.byType(AleraIconButton), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });
}
