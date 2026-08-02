import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show File, Platform;
import 'dart:isolate';

import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/presentation/terminal_buffer_budget.dart';
import 'package:alera/src/features/workbench/presentation/terminal_link_resolver.dart';
import 'package:alera/src/features/workbench/presentation/terminal_search_controller.dart';
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
part 'terminal_runtime_search.dart';
part 'terminal_runtime_session_recovery.dart';
part 'terminal_runtime_clipboard.dart';
part 'terminal_runtime_output_batching.dart';
part 'terminal_runtime_output_pipeline.dart';
part 'terminal_runtime_pointer_synchronization.dart';
part 'terminal_runtime_startup_delivery.dart';
part 'terminal_runtime_interactive_view.dart';
part 'terminal_runtime_shell_launches.dart';
part 'terminal_login_shell_launch.dart';
part 'terminal_runtime_rendering.dart';
part 'terminal_runtime_posix_io.dart';
part 'terminal_runtime_buffer_accounting.dart';
part 'terminal_runtime_restore_progress.dart';
part 'terminal_runtime_testing.dart';

abstract class TerminalSessionHandle extends ChangeNotifier {
  String get tabId;

  String get workspaceId;

  String get displayTitle;

  /// Title-only notifications.
  ///
  /// Shells emit an OSC title per prompt. Routing those through the handle's
  /// own notifier rebuilt the whole terminal view and every tab chip, so the
  /// tab strip listens here instead.
  ValueListenable<String> get titleListenable;

  /// Whether a visibility lease is currently held for this terminal.
  ///
  /// Defaulted so the many test doubles of this class do not each have to
  /// restate budget bookkeeping they have no buffer for.
  bool get isVisible => false;

  /// Buffer cost and last-visible time, used by the memory budget.
  TerminalBufferUsage get bufferUsage =>
      TerminalBufferUsage(tabId: tabId, bytes: 0, lastVisibleAt: null);

  /// Non-null while a restored scrollback snapshot is still being drained.
  ///
  /// Returning to an evicted terminal re-fetches its scrollback from the host
  /// and replays it through the frame batcher, which can take several frames.
  /// The surface shows a skeleton rather than an empty terminal so the wait
  /// does not read as lost history.
  ValueListenable<TerminalRestoreProgress?> get restoreProgress =>
      _neverRestoring;

  bool get isRunning;

  bool get isStarting;

  TerminalSessionOperation? get operation =>
      isStarting ? TerminalSessionOperation.starting : null;

  bool get canRestart => false;

  String? get errorMessage;

  Future<void> ensureStarted();

  Future<void> reconnect() => restart();

  Future<void> restart();

  TerminalVisibilityLease acquireVisibility();

  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  });

  /// Pulses the mounted PTY viewport and schedules a one-shot repaint.
  ///
  /// Handles without a measured view intentionally do nothing. Refreshing must
  /// never replace the emulator or the PTY session.
  Future<void> refreshRendering() async {}

  /// Moves keyboard focus to this terminal's text input so subsequent
  /// keypresses are routed to its PTY instead of any sidebar control.
  void requestFocus();

  /// Inserts [text] as if the user pasted it (bracketed paste when enabled).
  ///
  /// Default is a no-op so test doubles stay source-compatible.
  void pasteText(String text) {}

  /// The per-session terminal scrollback search model, when supported.
  TerminalSearchController? get searchController => null;

  /// Opens the search overlay for this terminal.
  void openSearch() {}

  /// Closes the search overlay for this terminal.
  void closeSearch() {}
}

enum TerminalSessionOperation { starting, reconnecting, restarting }

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

  /// The live handle for [tabId], or null. Never creates one.
  ///
  /// The tab strip renders a chip for every tab of the active workspace, and
  /// calling [sessionFor] there built a full handle, with its own xterm
  /// buffer, for tabs the user never opened.
  TerminalSessionHandle? peekSession(String tabId);

  /// Rechecks the buffer budget when the active workspace changes.
  void setActiveWorkspace(String? workspaceId);

  void closeTab(String tabId);

  void closeWorkspace(String workspaceId);

  void dispose();
}

/// Shared empty progress for handles that never restore a snapshot.
final ValueNotifier<TerminalRestoreProgress?> _neverRestoring =
    ValueNotifier<TerminalRestoreProgress?>(null);

/// How much of a restored snapshot has reached the emulator.
class TerminalRestoreProgress {
  const TerminalRestoreProgress({
    required this.writtenChars,
    required this.totalChars,
  });

  final int writtenChars;
  final int totalChars;

  double get fraction {
    if (totalChars <= 0) {
      return 1;
    }
    final value = writtenChars / totalChars;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }
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
    this.autoCloseOnSuccess = false,
  });

  final String workspaceId;
  final String tabId;
  final int exitCode;
  final bool autoCloseOnSuccess;
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

  /// Briefly applies an adjacent PTY size before restoring the measured size.
  ///
  /// This forces full-screen terminal apps to redraw without resizing the
  /// Flutter view or replacing the emulator.
  Future<void> refreshViewport(
    int cols,
    int rows,
    int cellWidthPx,
    int cellHeightPx,
  );

  Future<void> setOutputPaused(bool paused);

  void dispose();

  void terminate();
}

abstract interface class RecoverableTerminalPtySession
    implements TerminalPtySession {
  bool get supportsRestart;

  Future<void> reconnect();

  Future<void> restartProcess();
}

sealed class TerminalPtySessionEvent {
  const TerminalPtySessionEvent();
}

final class TerminalPtyOutputEvent extends TerminalPtySessionEvent {
  const TerminalPtyOutputEvent(this.data);

  final Uint8List data;
}

/// Output already decoded off the UI isolate. Byte-based PTY adapters keep
/// using [TerminalPtyOutputEvent]; only the socket path produces this.
final class TerminalPtyOutputTextEvent extends TerminalPtySessionEvent {
  const TerminalPtyOutputTextEvent(this.text);

  final String text;
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
