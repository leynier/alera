import 'dart:async';

import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/infra/runtime_editor_file_changes.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime file writes reload clean shared editors and preserve dirty buffers', () async {
    final registry = EditorSessionRegistry();
    final events = StreamController<RuntimeHostEvent>();
    final subscription = watchRuntimeEditorFileChanges(events.stream, registry);
    addTearDown(() async {
      await subscription.cancel();
      await events.close();
      registry.dispose();
    });
    for (final id in ['clean', 'other-task', 'dirty', 'unrelated']) {
      registry.documentFor(id)
        ..attachFile(
          workspacePath: id == 'unrelated' ? '/other' : '/repo',
          relativePath: 'a.txt',
        )
        ..acceptLoaded(
          native.WorkspaceEditorTextFile(
            rawContent: 'old',
            displayContent: 'old',
            contentToken: 'token',
            modifiedMillis: 0,
            size: .zero,
          ),
        );
    }
    registry.documentFor('dirty').updateCurrentText('unsaved');
    events.add(
      const RuntimeHostEvent('workspaceFilesChanged', {
        'workspacePath': '/repo',
        'relativePaths': ['a.txt'],
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(registry.documentFor('clean').hasSnapshot, isFalse);
    expect(registry.documentFor('other-task').hasSnapshot, isFalse);
    expect(registry.documentFor('dirty').currentText, 'unsaved');
    expect(registry.documentFor('dirty').contentToken, 'token');
    expect(registry.documentFor('unrelated').hasSnapshot, isTrue);
  });
}
