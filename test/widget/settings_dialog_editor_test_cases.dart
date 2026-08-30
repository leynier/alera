part of 'settings_dialog_test.dart';

void _registerSettingsDialogEditorTests() {
  testWidgets('edits and resets editor settings', (tester) async {
    final container = await _pumpSettingsDialog(tester);
    await tester.tap(find.text('Editor').first);
    await tester.pump();

    expect(find.text('Editor'), findsWidgets);
    expect(find.text('Tab Size'), findsOneWidget);
    expect(find.text('Theme Preset'), findsOneWidget);
    expect(find.text('Autosave'), findsWidgets);
    expect(find.text('Autosave Delay'), findsOneWidget);
    expect(container.read(settingsControllerProvider).editor.tabSize, 4);
    expect(
      container.read(settingsControllerProvider).editor.themeName,
      EditorSyntaxThemeNames.alera,
    );
    expect(
      container.read(settingsControllerProvider).editor.autosaveEnabled,
      isFalse,
    );
    expect(
      container.read(settingsControllerProvider).editor.autosaveDelaySeconds,
      EditorSettings.defaultAutosaveDelaySeconds,
    );

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container.read(settingsControllerProvider).editor.autosaveEnabled,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('editor-theme-search-field')),
      'monokai',
    );
    await tester.pump();
    await tester.tap(find.text(EditorSyntaxThemeNames.monokai));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).editor.themeName,
      EditorSyntaxThemeNames.monokai,
    );

    await tester.ensureVisible(find.text('Tab Size'));
    await tester.pump();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('editor-tab-size-row')),
        matching: find.byType(TextField),
      ),
      '2',
    );
    await tester.testTextInput.receiveAction(.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(settingsControllerProvider).editor.tabSize, 2);

    await tester.tap(find.text('Reset Editor'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).editor.tabSize,
      EditorSettings.defaults.tabSize,
    );
    expect(
      container.read(settingsControllerProvider).editor.themeName,
      EditorSettings.defaults.themeName,
    );
    expect(
      container.read(settingsControllerProvider).editor.autosaveEnabled,
      EditorSettings.defaults.autosaveEnabled,
    );
    expect(
      container.read(settingsControllerProvider).editor.autosaveDelaySeconds,
      EditorSettings.defaults.autosaveDelaySeconds,
    );
  });
}
