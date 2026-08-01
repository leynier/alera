import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_model_discovery_service.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:alera/src/features/settings/presentation/panes/terminal_theme_picker.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../unit/fake_project_config.dart';

part 'settings_dialog_core_test_cases.dart';
part 'settings_dialog_ai_text_test_cases.dart';
part 'settings_dialog_quota_test_cases.dart';
part 'settings_dialog_terminal_test_cases.dart';
part 'settings_dialog_interaction_test_cases.dart';
part 'settings_dialog_test_harness.dart';

Future<ProviderContainer> _pumpSettingsDialog(
  WidgetTester tester, {
  _FakeGitHubStarController? starController,
  AleraSettings initialSettings = AleraSettings.defaults,
  Size surfaceSize = const Size(1200, 900),
  SystemFontService? fontService,
  AiTextModelDiscoveryService? modelDiscoveryService,
  List<dynamic> extraOverrides = const <dynamic>[],
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // Keep MediaQuery in sync with the surface so the adaptive dialog sizing
  // (width/height fractions) sees the intended screen size.
  tester.view.physicalSize = surfaceSize * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
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
      aleraUpdateServiceProvider.overrideWithValue(_FakeUpdateService()),
      aiTextModelDiscoveryServiceProvider.overrideWithValue(
        modelDiscoveryService ?? const _FakeAiTextModelDiscoveryService(),
      ),
      if (starController != null)
        gitHubStarControllerProvider.overrideWith(() => starController),
      ...extraOverrides,
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
  _registerSettingsDialogAiTextTests();
  _registerSettingsDialogQuotaTests();
  _registerSettingsDialogTerminalTests();
  _registerSettingsDialogAdvancedTests();
}
