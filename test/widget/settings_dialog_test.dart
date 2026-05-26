import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  Future<ProviderContainer> pumpSettingsDialog(
    WidgetTester tester, {
    _FakeGitHubStarController? starController,
    AleraSettings initialSettings = AleraSettings.defaults,
    Size surfaceSize = const Size(1200, 900),
    SystemFontService? fontService,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeSettingsRepository(initialSettings);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        systemFontServiceProvider.overrideWithValue(
          fontService ??
              const _FakeSystemFontService(<String>[
                'Fira Code',
                'Menlo',
                'SF Mono',
              ]),
        ),
        updateServiceProvider.overrideWithValue(_FakeUpdateService()),
        if (starController != null)
          gitHubStarControllerProvider.overrideWith(() => starController),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const SettingsDialog(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  Future<void> selectTerminalSection(WidgetTester tester) async {
    // The sidebar lists General and Terminal — tap the Terminal nav item to
    // switch content. The first 'Terminal' text in the tree belongs to the
    // sidebar nav item (the section header inside the content uses titleLarge
    // and shows only when active).
    await tester.tap(find.text('Terminal').first);
    await tester.pump();
  }

  testWidgets('shows terminal settings and filters with search', (
    tester,
  ) async {
    await pumpSettingsDialog(tester);

    expect(find.text('Updates'), findsOneWidget);

    await selectTerminalSection(tester);

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Font family'), findsOneWidget);
    expect(find.text('Theme preset'), findsOneWidget);
    expect(find.text('Scrollback lines'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'cursor');
    await tester.pump();

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Cursor shape'), findsOneWidget);
    expect(find.text('Cursor opacity'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'missing setting');
    await tester.pump();

    expect(find.text('No settings found.'), findsOneWidget);
  });

  testWidgets('edits and resets terminal settings', (tester) async {
    final container = await pumpSettingsDialog(tester);
    await selectTerminalSection(tester);

    await tester.enterText(find.byType(TextField).at(2), '18');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(settingsControllerProvider).terminal.fontSize, 18);

    await tester.tap(
      find.byKey(const ValueKey<String>('terminal-font-family-field')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('terminal-font-family-field')),
      'Men',
    );
    await tester.pump();
    await tester.tap(find.text('Menlo'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontFamily,
      'Menlo',
    );

    await tester.ensureVisible(find.byTooltip('Bar'));
    await tester.pump();
    await tester.tap(find.byTooltip('Bar'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.cursorShape,
      TerminalCursorShape.bar,
    );

    await tester.ensureVisible(find.text('Blinking cursor'));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.cursorBlink,
      isTrue,
    );

    await tester.ensureVisible(find.text('Theme preset'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('terminal-theme-search-field')),
      'dracula',
    );
    await tester.pump();
    await tester.tap(find.text('Dracula'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.themeName,
      TerminalThemeNames.dracula,
    );

    await tester.dragFrom(const Offset(500, 240), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset terminal'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontSize,
      TerminalSettings.defaults.fontSize,
    );
    expect(
      container.read(settingsControllerProvider).terminal.cursorShape,
      TerminalCursorShape.block,
    );
    expect(
      container.read(settingsControllerProvider).terminal.themeName,
      TerminalSettings.defaults.themeName,
    );
  });

  testWidgets('theme picker stacks preview below the list on narrow widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 540,
            child: buildThemePickerSettingForTesting(
              value: TerminalThemeNames.aleraDark,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('terminal-theme-search-field')),
      findsOneWidget,
    );
    expect(find.text('Theme preset'), findsOneWidget);
  });

  testWidgets('edits destructive confirmation settings', (tester) async {
    final container = await pumpSettingsDialog(tester);

    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Confirm project removal'), findsOneWidget);
    expect(find.text('Confirm workspace removal'), findsOneWidget);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.confirmProjectRemoval,
      isFalse,
    );

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .general
          .confirmWorkspaceRemoval,
      isFalse,
    );

    await tester.enterText(find.byType(TextField).first, 'destructive');
    await tester.pump();

    expect(find.text('Confirm project removal'), findsOneWidget);
    expect(find.text('Confirm workspace removal'), findsOneWidget);
  });

  testWidgets('edits agent status notification settings', (tester) async {
    final container = await pumpSettingsDialog(tester);

    await tester.ensureVisible(find.text('Agent status notifications'));
    await tester.pump();

    expect(find.text('Agent status hooks'), findsOneWidget);
    expect(find.text('Agent status notifications'), findsOneWidget);

    await tester.tap(find.byType(Switch).at(2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(Switch).at(3));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusHooksEnabled,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusNotificationsEnabled,
      isTrue,
    );

    await tester.enterText(find.byType(TextField).first, 'notification');
    await tester.pump();

    expect(find.text('Agent status notifications'), findsOneWidget);
  });

  testWidgets('edits terminal color override via color picker dialog', (
    tester,
  ) async {
    final container = await pumpSettingsDialog(tester);
    await selectTerminalSection(tester);

    // Verify initial state: no foreground color override
    expect(
      container
          .read(settingsControllerProvider)
          .terminal
          .colorOverrides
          .foreground,
      isNull,
    );

    // Find the first color swatch (Foreground color swatch)
    final swatchFinder = find.byType(AleraColorSwatch).first;
    expect(swatchFinder, findsOneWidget);

    // Ensure the color swatch is visible
    await tester.ensureVisible(swatchFinder);
    await tester.pumpAndSettle();

    // Tap it to open the color picker dialog
    await tester.tap(swatchFinder);
    await tester.pumpAndSettle();

    // Verify the dialog has opened
    expect(find.text('Foreground color'), findsWidgets); // dialog title
    expect(find.byType(ColorPicker), findsOneWidget);

    // Simulate changing color in the picker to #112233
    final ColorPicker pickerWidget = tester.widget(find.byType(ColorPicker));
    pickerWidget.onColorChanged(const Color(0xFF112233));
    await tester.pump();

    // Tap Select
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    // Verify color override is updated to #112233
    expect(
      container
          .read(settingsControllerProvider)
          .terminal
          .colorOverrides
          .foreground,
      '#112233',
    );
  });

  testWidgets(
    'font autocomplete supports keyboard selection and empty-state dismissal',
    (tester) async {
      final container = await pumpSettingsDialog(tester);
      await selectTerminalSection(tester);

      final field = find.byKey(
        const ValueKey<String>('terminal-font-family-field'),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'sf');
      await tester.pump();

      expect(find.text('SF Mono'), findsWidgets);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'SF Mono',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'zzz');
      await tester.pump();

      expect(find.text('No matching fonts.'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('No matching fonts.'), findsNothing);
    },
  );

  testWidgets('workspace directory commits and clears overrides', (
    tester,
  ) async {
    final container = await pumpSettingsDialog(tester);
    final field = find.byType(TextField).at(1);

    await tester.enterText(field, '/tmp/alera-workspaces');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.workspaceDirectory,
      '/tmp/alera-workspaces',
    );

    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.workspaceDirectory,
      isNull,
    );
  });

  testWidgets(
    'support section can star Alera from not-starred and error states',
    (tester) async {
      final container = await pumpSettingsDialog(
        tester,
        starController: _FakeGitHubStarController(
          GitHubStarState.notStarred,
          nextStarState: GitHubStarState.starred,
        ),
      );

      expect(find.text('Support Alera'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);

      await tester.ensureVisible(find.text('Star'));
      await tester.pump();
      await tester.tap(find.text('Star'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thanks for the support!'), findsOneWidget);

      final errorController = _FakeGitHubStarController(
        GitHubStarState.error,
        nextStarState: GitHubStarState.starred,
      );
      container.dispose();
      await pumpSettingsDialog(tester, starController: errorController);

      expect(find.text('Try again'), findsOneWidget);

      await tester.ensureVisible(find.text('Try again'));
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thanks for the support!'), findsOneWidget);
    },
  );

  testWidgets('support section hides itself when starring is unavailable', (
    tester,
  ) async {
    await pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
    );

    expect(find.text('Support Alera'), findsNothing);
    expect(find.byKey(const ValueKey<String>('hidden')), findsNothing);
  });

  testWidgets('hidden star control shrinks away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildStarControlForTesting(
            state: GitHubStarState.hidden,
            onStar: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('hidden')), findsOneWidget);
  });

  testWidgets('edits additional terminal numeric and color overrides', (
    tester,
  ) async {
    final container = await pumpSettingsDialog(tester);
    await selectTerminalSection(tester);
    final before = container.read(settingsControllerProvider).terminal;

    Future<void> tapStepper(IconData icon, int index) async {
      final finder = find.byIcon(icon).at(index);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tapStepper(Icons.keyboard_arrow_up, 1);
    await tapStepper(Icons.keyboard_arrow_up, 2);
    await tapStepper(Icons.keyboard_arrow_down, 3);
    await tapStepper(Icons.keyboard_arrow_down, 4);
    await tapStepper(Icons.keyboard_arrow_up, 5);
    await tapStepper(Icons.keyboard_arrow_up, 6);
    await tapStepper(Icons.keyboard_arrow_up, 7);
    await tapStepper(Icons.keyboard_arrow_up, 8);
    await tapStepper(Icons.keyboard_arrow_up, 9);
    await tapStepper(Icons.keyboard_arrow_up, 10);

    Future<void> setSwatchColor(int index, Color color) async {
      final swatch = find.byType(AleraColorSwatch).at(index);
      await tester.ensureVisible(swatch);
      await tester.pumpAndSettle();
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      final picker = tester.widget<ColorPicker>(find.byType(ColorPicker));
      picker.onColorChanged(color);
      await tester.pump();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
    }

    await setSwatchColor(1, const Color(0xFF223344));
    await setSwatchColor(2, const Color(0xFF445566));
    await setSwatchColor(3, const Color(0xFF667788));

    final after = container.read(settingsControllerProvider).terminal;
    expect(after.fontWeight, greaterThan(before.fontWeight));
    expect(after.lineHeight, greaterThan(before.lineHeight));
    expect(after.cursorOpacity, lessThan(before.cursorOpacity));
    expect(after.backgroundOpacity, lessThan(before.backgroundOpacity));
    expect(after.paddingX, greaterThan(before.paddingX));
    expect(after.paddingY, greaterThan(before.paddingY));
    expect(after.scrollbackLines, greaterThan(before.scrollbackLines));
    expect(after.hostScrollbackBytes, greaterThan(before.hostScrollbackBytes));
    expect(
      after.hostEmptyShutdownDelaySeconds,
      greaterThan(before.hostEmptyShutdownDelaySeconds),
    );
    expect(
      after.hostDetachedSessionShutdownDelaySeconds,
      greaterThan(before.hostDetachedSessionShutdownDelaySeconds),
    );
    expect(after.colorOverrides.background, '#223344');
    expect(after.colorOverrides.cursor, '#445566');
    expect(after.colorOverrides.selection, '#667788');
  });

  testWidgets('font autocomplete clears, toggles, and commits custom values', (
    tester,
  ) async {
    final container = await pumpSettingsDialog(tester);
    await selectTerminalSection(tester);

    final field = find.byKey(
      const ValueKey<String>('terminal-font-family-field'),
    );

    await tester.tap(field);
    await tester.pump();
    await tester.tap(find.byTooltip('Fonts'));
    await tester.pump();

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();

    await tester.enterText(field, 'Custom Mono');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontFamily,
      'Custom Mono',
    );
  });

  testWidgets('workspace directory browse commits the picked folder', (
    tester,
  ) async {
    final previousPlatform = FileSelectorPlatform.instance;
    final fakePlatform = _FakeFileSelectorPlatform(<Object?>[
      '/tmp/picked-workspaces',
    ]);
    FileSelectorPlatform.instance = fakePlatform;
    addTearDown(() => FileSelectorPlatform.instance = previousPlatform);

    final container = await pumpSettingsDialog(tester);
    final field = find.byType(TextField).at(1);
    await tester.enterText(field, '/tmp/current-workspaces');
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Browse'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsControllerProvider).general.workspaceDirectory,
      '/tmp/picked-workspaces',
    );
    expect(
      fakePlatform.requests.single.initialDirectory,
      '/tmp/current-workspaces',
    );
    expect(
      fakePlatform.requests.single.confirmButtonText,
      'Use as workspace directory',
    );
  });

  testWidgets('font autocomplete supports arrow-up and numpad enter', (
    tester,
  ) async {
    final container = await pumpSettingsDialog(tester);
    await selectTerminalSection(tester);

    final field = find.byKey(
      const ValueKey<String>('terminal-font-family-field'),
    );
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'sf');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontFamily,
      'SF Mono',
    );
  });

  testWidgets('keyboard search fallback and close actions dismiss the dialog', (
    tester,
  ) async {
    await pumpSettingsDialog(tester);

    await tester.tap(find.text('Keyboard').first);
    await tester.pump();
    expect(find.text('When a terminal is focused'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'confirm');
    await tester.pump();
    expect(find.text('Confirm project removal'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('no-results close button dismisses the dialog', (tester) async {
    await pumpSettingsDialog(tester);

    await tester.enterText(find.byType(TextField).first, 'missing setting');
    await tester.pump();
    expect(find.text('No settings found.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets(
    'word separators commits, clears, and resets from parent updates',
    (tester) async {
      final container = await pumpSettingsDialog(tester);
      await selectTerminalSection(tester);

      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == " ()[]{},\"'`",
      );

      await tester.enterText(field, '.,');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        '.,',
      );

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        isNull,
      );

      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        'abc',
      );

      await container
          .read(settingsControllerProvider.notifier)
          .resetTerminalSettings();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        isNull,
      );
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);
    },
  );

  testWidgets(
    'font autocomplete covers closed-menu commits and hover selection',
    (tester) async {
      final container = await pumpSettingsDialog(tester);
      await selectTerminalSection(tester);

      final field = find.byKey(
        const ValueKey<String>('terminal-font-family-field'),
      );

      await tester.enterText(field, 'Custom Mono');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'sf');
      await tester.pump();
      await tester.tap(find.byTooltip('Fonts'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'SF Mono',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Menlo Custom');
      await tester.pump();
      await tester.tap(find.byTooltip('Fonts'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo Custom',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'm');
      await tester.pump();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.text('Menlo')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo',
      );
      expect(tester.widget<AleraTextField>(field).controller?.text, 'Menlo');
    },
  );

  testWidgets('theme picker falls back and tracks hover state', (tester) async {
    final container = await pumpSettingsDialog(
      tester,
      initialSettings: AleraSettings.defaults.copyWith(
        terminal: AleraSettings.defaults.terminal.copyWith(
          themeName: 'missing-theme',
        ),
      ),
    );
    await selectTerminalSection(tester);

    expect(find.text('Selected: Alera Dark'), findsOneWidget);
    expect(find.text(r'$ git status --short'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('terminal-theme-search-field')),
      'drac',
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await tester.ensureVisible(find.text('Dracula'));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Dracula')));
    await tester.pump();
    await tester.tap(find.text('Dracula'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.themeName,
      TerminalThemeNames.dracula,
    );
  });

  testWidgets(
    'workspace browse falls back to the stored directory when the field is empty',
    (tester) async {
      final previousPlatform = FileSelectorPlatform.instance;
      final fakePlatform = _FakeFileSelectorPlatform(<Object?>[
        '/tmp/fallback-picked-workspaces',
      ]);
      FileSelectorPlatform.instance = fakePlatform;
      addTearDown(() => FileSelectorPlatform.instance = previousPlatform);

      final container = await pumpSettingsDialog(
        tester,
        initialSettings: AleraSettings.defaults.copyWith(
          general: AleraSettings.defaults.general.copyWith(
            workspaceDirectory: '/tmp/existing-workspaces',
          ),
        ),
      );
      final field = find.byType(TextField).at(1);

      await tester.enterText(field, '');
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse'));
      await tester.pumpAndSettle();

      expect(
        fakePlatform.requests.single.initialDirectory,
        '/tmp/existing-workspaces',
      );
      expect(
        container.read(settingsControllerProvider).general.workspaceDirectory,
        '/tmp/fallback-picked-workspaces',
      );
    },
  );

  testWidgets(
    'font autocomplete refreshes suggestions when async fonts arrive',
    (tester) async {
      final fontsCompleter = Completer<List<String>>();
      await pumpSettingsDialog(
        tester,
        fontService: _DelayedSystemFontService(fontsCompleter.future),
      );
      await selectTerminalSection(tester);

      final field = find.byKey(
        const ValueKey<String>('terminal-font-family-field'),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'alera');
      await tester.pump();

      expect(find.text('Alera Mono'), findsNothing);

      fontsCompleter.complete(<String>['Alera Mono']);
      await tester.pump();
      await tester.pump();

      expect(find.text('Alera Mono'), findsWidgets);
    },
  );

  testWidgets(
    'hex color fields commit, clear invalid input, and reset on updates',
    (tester) async {
      final container = await pumpSettingsDialog(tester);
      await selectTerminalSection(tester);

      final field = find.byWidgetPredicate(
        (widget) => widget is AleraTextField && widget.hintText == '#101010',
      );
      await tester.ensureVisible(field);
      await tester.pump();

      await tester.enterText(field, '#123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container
            .read(settingsControllerProvider)
            .terminal
            .colorOverrides
            .background,
        '#123456',
      );

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container
            .read(settingsControllerProvider)
            .terminal
            .colorOverrides
            .background,
        isNull,
      );

      await tester.enterText(field, 'bad');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<AleraTextField>(field).controller?.text, isEmpty);

      await tester.enterText(field, '#abcdef');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));

      await container
          .read(settingsControllerProvider.notifier)
          .resetTerminalSettings();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container
            .read(settingsControllerProvider)
            .terminal
            .colorOverrides
            .background,
        isNull,
      );
      expect(tester.widget<AleraTextField>(field).controller?.text, isEmpty);
    },
  );
}

class _FakeUpdateService implements AleraUpdateService {
  @override
  final AleraUpdateConfig config = AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://github.com/leynier/alera'),
    channel: AleraUpdateChannel.stable,
    autoInstallEnabled: false,
    signedRelease: false,
  );

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    return const AleraUpdateCheckResult(message: 'Alera is up to date.');
  }

  @override
  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {}

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {}

  @override
  Future<void> restartApp() async {}

  @override
  void dispose() {}
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

class _FakeSystemFontService implements SystemFontService {
  const _FakeSystemFontService(this.fonts);

  final List<String> fonts;

  @override
  Future<List<String>> listFontFamilies() async => fonts;
}

class _DelayedSystemFontService implements SystemFontService {
  _DelayedSystemFontService(this.futureFonts);

  final Future<List<String>> futureFonts;

  @override
  Future<List<String>> listFontFamilies() => futureFonts;
}

class _FakeGitHubStarController extends GitHubStarController {
  _FakeGitHubStarController(this.initialState, {this.nextStarState});

  final GitHubStarState initialState;
  final GitHubStarState? nextStarState;

  @override
  GitHubStarState build() => initialState;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> star() async {
    if (state != GitHubStarState.notStarred && state != GitHubStarState.error) {
      return;
    }
    state = GitHubStarState.starring;
    state = nextStarState ?? GitHubStarState.starred;
  }
}

class _FakeFileSelectorPlatform extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelectorPlatform(this.responses);

  final List<Object?> responses;
  final List<_DirectoryRequest> requests = <_DirectoryRequest>[];

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    requests.add(
      _DirectoryRequest(
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      ),
    );
    if (responses.isEmpty) {
      return null;
    }
    final next = responses.removeAt(0);
    if (next is Object && next is! String) {
      throw next;
    }
    return next as String?;
  }
}

class _DirectoryRequest {
  const _DirectoryRequest({
    required this.initialDirectory,
    required this.confirmButtonText,
  });

  final String? initialDirectory;
  final String? confirmButtonText;
}
