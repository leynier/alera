import 'dart:async';

import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

StreamSubscription<RuntimeHostEvent> watchRuntimeEditorFileChanges(
  Stream<RuntimeHostEvent> events,
  EditorSessionRegistry registry,
) => events.listen((event) {
  if (event.name != 'workspaceFilesChanged') return;
  final workspacePath = event.payload['workspacePath'];
  final paths = event.payload['relativePaths'];
  if (workspacePath is! String || paths is! List) return;
  registry.reloadCleanFiles(
    workspacePath: workspacePath,
    relativePaths: paths.whereType<String>(),
  );
});
