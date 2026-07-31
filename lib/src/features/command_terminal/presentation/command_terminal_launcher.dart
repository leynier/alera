import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/command_terminal/application/command_terminal_session.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Runs [request] in a terminal dialog and returns once the dialog is gone.
///
/// This is the shared entry point for every "show the user what this command is
/// doing" flow. Callers pass a command and a title; the session, its teardown
/// and the confirm-before-killing are handled here.
Future<void> showCommandTerminalDialog(
  BuildContext context,
  WidgetRef ref,
  CommandTerminalRequest request,
) async {
  final runtime = ref.read(terminalRuntimeProvider);
  // The inherited directory is the last resort rather than a default: a
  // GUI-launched app has whatever the launcher had, which on Windows is
  // typically a place installers cannot write to.
  final workingDirectory =
      request.workingDirectory ??
      commandTerminalHomeDirectory(Platform.environment) ??
      Directory.current.path;
  final tabId = const Uuid().v4();
  final session = openCommandTerminalSession(
    runtime: runtime,
    request: request,
    tabId: tabId,
    workingDirectory: workingDirectory,
  );
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommandTerminalDialog(request: request, session: session),
    );
  } finally {
    // Owning the teardown here is what lets the workbench exit coordinator stay
    // out of this session: closing terminates the shell's whole process tree.
    runtime.closeTab(tabId);
  }
}
