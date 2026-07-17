import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show File, Platform;
import 'dart:isolate';

import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/presentation/terminal_link_resolver.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/workbench/domain/terminal_agent_prompt_injection.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:alera/src/features/workbench/domain/terminal_mode_reset.dart';
import 'package:alera/src/features/workbench/domain/terminal_osc52_clipboard.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:portable_pty/portable_pty.dart';
import 'package:xterm/xterm.dart' as xterm;

part 'terminal_runtime_posix_adapter.dart';
part 'terminal_runtime_ghostty_adapter.dart';
part 'terminal_runtime_xterm_runtime.dart';
part 'terminal_runtime_session_handle.dart';
part 'terminal_runtime_clipboard.dart';
part 'terminal_runtime_output_batching.dart';
part 'terminal_runtime_startup_delivery.dart';
part 'terminal_runtime_interactive_view.dart';
part 'terminal_runtime_shell_launches.dart';
part 'terminal_runtime_posix_io.dart';
part 'terminal_runtime_testing.dart';

abstract class TerminalSessionHandle extends ChangeNotifier {
  String get tabId;

  String get workspaceId;

  String get displayTitle;

  bool get isRunning;

  bool get isStarting;

  String? get errorMessage;

  Future<void> ensureStarted();

  Future<void> restart();

  TerminalVisibilityLease acquireVisibility();

  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  });

  /// Moves keyboard focus to this terminal's text input so subsequent
  /// keypresses are routed to its PTY instead of any sidebar control.
  void requestFocus();
}

abstract interface class TerminalVisibilityLease {
  void dispose();
}

final class NoopTerminalVisibilityLease implements TerminalVisibilityLease {
  const NoopTerminalVisibilityLease();

  @override
  void dispose() {}
}

abstract interface class TerminalRuntime {
  Stream<TerminalRuntimeExitEvent> get exits;

  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  });

  void closeTab(String tabId);

  void closeWorkspace(String workspaceId);

  void dispose();
}

typedef TerminalLaunchEnvironmentBuilder =
    FutureOr<Map<String, String>?> Function({
      required String terminalSessionId,
      required String workspaceId,
      required String tabId,
    });

typedef TerminalSessionCleanup =
    FutureOr<void> Function(String terminalSessionId);

typedef TerminalProcessCreated =
    FutureOr<void> Function(String terminalSessionId);

final class TerminalRuntimeExitEvent {
  const TerminalRuntimeExitEvent({
    required this.workspaceId,
    required this.tabId,
    required this.exitCode,
  });

  final String workspaceId;
  final String tabId;
  final int exitCode;
}

abstract interface class TerminalPtySessionFactory {
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  });
}

abstract interface class TerminalPtySession {
  Stream<TerminalPtySessionEvent> get events;

  bool get startedNewProcess;

  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
    Future<void> Function()? onProcessCreated,
  });

  bool writeBytes(List<int> bytes);

  Future<bool> writeBytesAndWait(List<int> bytes);

  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx);

  Future<void> setOutputPaused(bool paused);

  void dispose();

  void terminate();
}

sealed class TerminalPtySessionEvent {
  const TerminalPtySessionEvent();
}

final class TerminalPtyOutputEvent extends TerminalPtySessionEvent {
  const TerminalPtyOutputEvent(this.data);

  final Uint8List data;
}

final class TerminalPtySnapshotEvent extends TerminalPtySessionEvent {
  const TerminalPtySnapshotEvent(
    this.data, {
    this.resetInteractionModes = false,
  });

  final Uint8List data;
  final bool resetInteractionModes;
}

final class TerminalPtyExitEvent extends TerminalPtySessionEvent {
  const TerminalPtyExitEvent(this.exitCode, {this.notifyRuntime = true});

  final int exitCode;
  final bool notifyRuntime;
}

final class TerminalPtyErrorEvent extends TerminalPtySessionEvent {
  const TerminalPtyErrorEvent(this.error);

  final Object error;
}

class DefaultTerminalPtySessionFactory implements TerminalPtySessionFactory {
  const DefaultTerminalPtySessionFactory();

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      return _PosixPortablePtySessionAdapter();
    }
    return _GhosttyTerminalPtySessionAdapter();
  }
}
