import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/gestures.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/terminal_agent_prompt_injection.dart';
import 'package:alera/src/features/workbench/domain/terminal_mode_reset.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:xterm2/xterm.dart' as xterm;

part 'terminal_runtime_helper_group.dart';
part 'terminal_login_shell_group.dart';
part 'terminal_runtime_factory_group.dart';
part 'terminal_runtime_clipboard_cases.dart';
part 'terminal_runtime_xterm_session_cases.dart';
part 'terminal_runtime_xterm_buffer_boundary_cases.dart';
part 'terminal_runtime_snapshot_cases.dart';
part 'terminal_buffer_eviction_cases.dart';
part 'terminal_runtime_output_backpressure_cases.dart';
part 'terminal_runtime_remint_cases.dart';
part 'terminal_runtime_pulse_cases.dart';
part 'terminal_runtime_xterm_widget_cases.dart';
part 'terminal_runtime_native_test_harness.dart';

void main() {
  _registerTerminalRuntimeHelperGroup();
  _registerTerminalLoginShellGroup();
  _registerTerminalRuntimeFactoryGroup();
  group('XtermTerminalRuntime', () {
    _registerXtermRuntimeClipboardTests();
    _registerXtermRuntimeSessionTests();
    _registerXtermRuntimeBufferBoundaryTests();
    _registerTerminalRuntimeSnapshotTests();
    _registerTerminalBufferEvictionTests();
    _registerTerminalRuntimeOutputBackpressureTests();
    _registerXtermRuntimeRemintTests();
    _registerTerminalRuntimePulseTests();
    _registerXtermRuntimeWidgetTests();
  });
}
