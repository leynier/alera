import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:xterm/xterm.dart' as xterm;

part 'terminal_surface_core_test_cases.dart';
part 'terminal_surface_composer_test_cases.dart';
part 'terminal_surface_composer_submit_test_cases.dart';
part 'terminal_surface_interaction_test_cases.dart';
part 'terminal_surface_tab_switch_test_cases.dart';
part 'terminal_surface_toolbar_test_cases.dart';
part 'terminal_surface_test_harness.dart';

void main() {
  _registerTerminalSurfaceRuntimeTests();
  _registerTerminalSurfaceComposerTests();
  _registerTerminalSurfaceComposerSubmitTests();
  _registerTerminalSurfaceInteractionTests();
  _registerTerminalSurfaceTabSwitchTests();
  _registerTerminalSurfaceToolbarTests();
}
