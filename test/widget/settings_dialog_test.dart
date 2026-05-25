import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpSettingsDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeSettingsRepository();
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(repository, loadOnCreate: false),
        ),
        systemFontServiceProvider.overrideWithValue(
          const _FakeSystemFontService(<String>[
            'Fira Code',
            'Menlo',
            'SF Mono',
          ]),
        ),
        updateServiceProvider.overrideWithValue(_FakeUpdateService()),
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
  AleraSettings _settings = AleraSettings.defaults;

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
