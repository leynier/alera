part of 'settings_dialog_test.dart';

void _registerSettingsDialogTerminalTests() {
  testWidgets('edits additional terminal numeric and color overrides', (
    tester,
  ) async {
    final container = await _pumpSettingsDialog(tester);
    await _selectTerminalSection(tester);
    final before = container.read(settingsControllerProvider).terminal;

    // Scope to the i-th number field: the up/down chevrons are shared with
    // expander rows, so a global icon index would no longer be unique.
    Future<void> tapStepper(IconData icon, int index) async {
      final finder = find.descendant(
        of: find.byType(AleraNumberField).at(index),
        matching: find.byIcon(icon),
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tapStepper(AleraIcons.chevronUp, 1);
    await tapStepper(AleraIcons.chevronUp, 2);
    await tapStepper(AleraIcons.chevronDown, 3);
    await tapStepper(AleraIcons.chevronDown, 4);
    await tapStepper(AleraIcons.chevronUp, 5);
    await tapStepper(AleraIcons.chevronUp, 6);
    await tapStepper(AleraIcons.chevronUp, 7);
    await tapStepper(AleraIcons.chevronUp, 8);
    await tapStepper(AleraIcons.chevronUp, 9);

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
    expect(
      after.tuiScrollSensitivity,
      greaterThan(before.tuiScrollSensitivity),
    );
    expect(after.scrollbackLines, greaterThan(before.scrollbackLines));
    expect(after.hostScrollbackBytes, greaterThan(before.hostScrollbackBytes));
    expect(after.colorOverrides.background, '#223344');
    expect(after.colorOverrides.cursor, '#445566');
    expect(after.colorOverrides.selection, '#667788');
  });
}
