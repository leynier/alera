import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_command_palette_dialog.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('filters commands and executes the selected action', (
    tester,
  ) async {
    KeyboardActionId? executed;
    await _pumpCommandPalette(tester, onExecute: (id) => executed = id);

    await tester.tap(find.text('Open Command Palette'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quick');
    await tester.pump();

    expect(find.text('Quick Open'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<KeyboardActionId>(KeyboardActionId.openCommandPalette),
      ),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(executed, KeyboardActionId.openQuickOpen);
    expect(find.text('Command Palette'), findsNothing);
  });

  testWidgets('Escape closes and restores focus', (tester) async {
    final anchorFocus = FocusNode();
    addTearDown(anchorFocus.dispose);
    await _pumpCommandPalette(tester, anchorFocus: anchorFocus);
    anchorFocus.requestFocus();
    await tester.pump();

    await tester.tap(find.text('Open Command Palette'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a command');
    await tester.pump();
    expect(find.text('No commands match "not a command".'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Command Palette'), findsNothing);
    expect(anchorFocus.hasFocus, isTrue);
  });
}

Future<void> _pumpCommandPalette(
  WidgetTester tester, {
  ValueChanged<KeyboardActionId>? onExecute,
  FocusNode? anchorFocus,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(
          () => _CommandPaletteSettingsController(AleraSettings.defaults),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: anchorFocus,
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showKeyboardCommandPalette(
                  context,
                  onExecute: onExecute ?? (_) {},
                ),
                child: const Text('Open Command Palette'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _CommandPaletteSettingsController extends SettingsController {
  _CommandPaletteSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}
