import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('DeferredWorkspaceSetupLauncher');

Future<WorkspaceCreationResult> launchDeferredWorkspaceSetup(
  MobileTerminalClient client,
  WorkspaceCreationResult creation,
) async {
  final command = creation.deferredSetupCommand?.trim();
  if (command == null || command.isEmpty) {
    return creation;
  }

  MobileTerminalSession? session;
  try {
    session = await client.createTerminal(
      creation.workspace.id,
      title: 'Setup',
      autoCloseOnSuccess: true,
    );
    final supportsDeferredInput = client.supportsDeferredTerminalInput;
    final startupCommand = _autoCloseSetupCommand(command);
    await client.writeTerminal(
      session.attachment.sessionId,
      utf8.encode(supportsDeferredInput ? startupCommand : '$startupCommand\r'),
      deferredEnter: supportsDeferredInput,
    );
    return creation;
  } on Object catch (error, stackTrace) {
    _logger.warning(
      'could not start deferred setup for ${creation.workspace.id}',
      error,
      stackTrace,
    );
    return creation.withSetupLaunchError(error);
  } finally {
    final sessionId = session?.attachment.sessionId;
    if (sessionId != null) {
      try {
        await client.detachTerminal(sessionId);
      } on Object catch (error, stackTrace) {
        _logger.warning(
          'could not detach deferred setup terminal for ${creation.workspace.id}',
          error,
          stackTrace,
        );
      }
    }
  }
}

String _autoCloseSetupCommand(String command) {
  if (command.startsWith('/bin/sh ')) {
    return 'exec $command';
  }
  if (command.startsWith('cmd ')) {
    return '$command & exit /b';
  }
  return command;
}
