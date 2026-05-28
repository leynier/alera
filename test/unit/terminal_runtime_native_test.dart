import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/gestures.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:xterm/xterm.dart' as xterm;

part 'terminal_runtime_helper_group.dart';
part 'terminal_runtime_factory_group.dart';
part 'terminal_runtime_xterm_session_cases.dart';
part 'terminal_runtime_xterm_widget_cases.dart';
part 'terminal_runtime_native_test_harness.dart';

void main() {
  _registerTerminalRuntimeHelperGroup();
  _registerTerminalRuntimeFactoryGroup();
  group('XtermTerminalRuntime', () {
    _registerXtermRuntimeSessionTests();
    _registerXtermRuntimeWidgetTests();
  });
}
