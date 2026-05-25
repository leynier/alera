import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpPane(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(
            _FakeSettingsRepository(),
            loadOnCreate: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: KeyboardSettingsPane()),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  KeyboardShortcutSettingsReader keyboardOf(ProviderContainer container) {
    return KeyboardShortcutSettingsReader(container);
  }

  testWidgets('renders registry actions and the policy selector', (
    tester,
  ) async {
    await pumpPane(tester);

    expect(find.text('Behavior'), findsOneWidget);
    expect(find.text('New terminal tab'), findsOneWidget);
    expect(find.text('Close tab'), findsOneWidget);
    expect(find.text('Split right'), findsOneWidget);
    expect(find.text('App first'), findsOneWidget);
    expect(find.text('Terminal first'), findsOneWidget);
  });

  testWidgets('changing the terminal policy persists', (tester) async {
    final container = await pumpPane(tester);

    await tester.tap(find.text('Terminal first'));
    await tester.pump();

    expect(
      keyboardOf(container).policy,
      TerminalShortcutPolicy.terminalFirst,
    );
  });

  testWidgets('recording a free chord saves an override', (tester) async {
    final container = await pumpPane(tester);

    // Enter recording mode for "New terminal tab".
    final row = find.ancestor(
      of: find.text('New terminal tab'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byTooltip('Change shortcut')),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      keyboardOf(container).overrideFor(KeyboardActionId.newTerminalTab),
      <String>['Mod+Shift+K'],
    );
  });

  testWidgets('recording a conflicting chord blocks and can reassign', (
    tester,
  ) async {
    final container = await pumpPane(tester);

    // Record Ctrl+W for "New terminal tab"; Ctrl+W already maps to "Close tab".
    final row = find.ancestor(
      of: find.text('New terminal tab'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byTooltip('Change shortcut')),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('Shortcut already in use'), findsOneWidget);

    await tester.tap(find.text('Reassign'));
    await tester.pumpAndSettle();

    expect(
      keyboardOf(container).overrideFor(KeyboardActionId.newTerminalTab),
      <String>['Mod+W'],
    );
    // The previous owner loses the chord.
    expect(
      keyboardOf(container).overrideFor(KeyboardActionId.closeTab),
      isEmpty,
    );
  });
}

/// Thin reader over the container's keyboard settings for assertions.
class KeyboardShortcutSettingsReader {
  KeyboardShortcutSettingsReader(this.container);

  final ProviderContainer container;

  TerminalShortcutPolicy get policy =>
      container.read(settingsControllerProvider).keyboard.terminalPolicy;

  List<String>? overrideFor(KeyboardActionId id) =>
      container.read(settingsControllerProvider).keyboard.overrides[id];
}

class _FakeSettingsRepository implements SettingsRepository {
  AleraSettings _settings = AleraSettings.defaults;

  @override
  Future<AleraSettings> load() async => _settings;

  @override
  Future<void> save(AleraSettings settings) async {
    _settings = settings;
  }
}
