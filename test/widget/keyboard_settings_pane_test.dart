import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpPane(
    WidgetTester tester, {
    AleraSettings initialSettings = AleraSettings.defaults,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _FakeSettingsRepository(initialSettings),
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
    expect(find.text('New Terminal Tab'), findsOneWidget);
    expect(find.text('Close Tab'), findsOneWidget);
    expect(find.text('Split Right'), findsOneWidget);
    expect(find.text('App First'), findsOneWidget);
    expect(find.text('Terminal First'), findsOneWidget);
  });

  testWidgets('changing the terminal policy persists', (tester) async {
    final container = await pumpPane(tester);

    await tester.tap(find.text('Terminal First'));
    await tester.pump();

    expect(keyboardOf(container).policy, TerminalShortcutPolicy.terminalFirst);
  });

  testWidgets('recording a free chord saves an override', (tester) async {
    final container = await pumpPane(tester);

    // Enter recording mode for "New Terminal Tab".
    final row = find.ancestor(
      of: find.text('New Terminal Tab'),
      matching: find.byType(Row),
    );
    final changeShortcut = find.descendant(
      of: row.first,
      matching: find.byTooltip('Change Shortcut'),
    );
    await tester.ensureVisible(changeShortcut);
    await tester.pump();
    await tester.tap(changeShortcut);
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

    // Record Ctrl+W for "New Terminal Tab"; Ctrl+W already maps to "Close Tab".
    final row = find.ancestor(
      of: find.text('New Terminal Tab'),
      matching: find.byType(Row),
    );
    final changeShortcut = find.descendant(
      of: row.first,
      matching: find.byTooltip('Change Shortcut'),
    );
    await tester.ensureVisible(changeShortcut);
    await tester.pump();
    await tester.tap(changeShortcut);
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

  testWidgets(
    'recording can toggle off, cancel with escape, and show parse errors',
    (tester) async {
      await pumpPane(tester);

      final row = find.ancestor(
        of: find.text('New Terminal Tab'),
        matching: find.byType(Row),
      );

      Future<void> startRecording() async {
        final changeShortcut = find.descendant(
          of: row.first,
          matching: find.byTooltip('Change Shortcut'),
        );
        await tester.ensureVisible(changeShortcut);
        await tester.pump();
        await tester.tap(changeShortcut);
        await tester.pump();
      }

      await startRecording();
      expect(find.text('Press keys… (Esc to cancel)'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: row.first,
          matching: find.byTooltip('Stop Recording'),
        ),
      );
      await tester.pump();
      expect(find.text('Press keys… (Esc to cancel)'), findsNothing);

      await startRecording();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Press keys… (Esc to cancel)'), findsNothing);

      await startRecording();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('Include at least one modifier key.'), findsOneWidget);
    },
  );

  testWidgets('reset and disable actions persist shortcut changes', (
    tester,
  ) async {
    final initialSettings = AleraSettings.defaults.copyWith(
      keyboard: AleraSettings.defaults.keyboard.copyWithOverride(
        KeyboardActionId.newTerminalTab,
        <String>['Mod+Shift+K'],
      ),
    );
    final container = await pumpPane(tester, initialSettings: initialSettings);

    final newTabRow = find.ancestor(
      of: find.text('New Terminal Tab'),
      matching: find.byType(Row),
    );
    final resetNewTab = find.descendant(
      of: newTabRow.first,
      matching: find.byTooltip('Reset to Default'),
    );
    await tester.ensureVisible(resetNewTab);
    await tester.pump();
    await tester.tap(resetNewTab);
    await tester.pump();

    expect(
      keyboardOf(container).overrideFor(KeyboardActionId.newTerminalTab),
      isNull,
    );

    final closeTabRow = find.ancestor(
      of: find.text('Close Tab'),
      matching: find.byType(Row),
    );
    final disableCloseTab = find.descendant(
      of: closeTabRow.first,
      matching: find.byTooltip('Disable Shortcut'),
    );
    await tester.ensureVisible(disableCloseTab);
    await tester.pump();
    await tester.tap(disableCloseTab);
    await tester.pump();

    expect(
      keyboardOf(container).overrideFor(KeyboardActionId.closeTab),
      isEmpty,
    );
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('invalid shortcut overrides render as unassigned', (
    tester,
  ) async {
    final initialSettings = AleraSettings.defaults.copyWith(
      keyboard: AleraSettings.defaults.keyboard.copyWithOverride(
        KeyboardActionId.newTerminalTab,
        <String>['definitely not a shortcut'],
      ),
    );

    await pumpPane(tester, initialSettings: initialSettings);

    final newTabRow = find
        .ancestor(of: find.text('New Terminal Tab'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: newTabRow, matching: find.text('Unassigned')),
      findsOneWidget,
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
  _FakeSettingsRepository([AleraSettings? initialSettings])
    : _settings = initialSettings ?? AleraSettings.defaults;

  AleraSettings _settings;

  @override
  Future<AleraSettings> load() async => _settings;

  @override
  Future<void> save(AleraSettings settings) async {
    _settings = settings;
  }
}
