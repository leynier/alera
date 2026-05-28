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

part 'settings_dialog_core_test_cases.dart';
part 'settings_dialog_interaction_test_cases.dart';
part 'settings_dialog_test_harness.dart';

Future<ProviderContainer> _pumpSettingsDialog(
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

Future<void> _selectTerminalSection(WidgetTester tester) async {
  await tester.tap(find.text('Terminal').first);
  await tester.pump();
}

void main() {
  _registerSettingsDialogCoreTests();
  _registerSettingsDialogAdvancedTests();
}
