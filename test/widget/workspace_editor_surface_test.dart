import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes editor tab size to the supported range', () {
    expect(normalizeWorkspaceEditorTabSize(4), 4);
    expect(normalizeWorkspaceEditorTabSize(0), 1);
    expect(normalizeWorkspaceEditorTabSize(12), 8);
  });

  testWidgets('suppresses stale focus callbacks during editor teardown', (
    tester,
  ) async {
    final focusNode = WorkspaceEditorFocusNode();
    addTearDown(focusNode.dispose);
    var calls = 0;
    focusNode.addListener(() {
      calls += 1;
    });

    await tester.pumpWidget(
      Focus(focusNode: focusNode, child: const SizedBox()),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(calls, greaterThan(0));
    final callsBeforeSuppression = calls;

    focusNode.suppressThirdPartyListeners();
    focusNode.unfocus();
    await tester.pump();

    expect(calls, callsBeforeSuppression);
  });

  testWidgets('removes wrapped focus listeners by their original callback', (
    tester,
  ) async {
    final focusNode = WorkspaceEditorFocusNode();
    addTearDown(focusNode.dispose);
    var calls = 0;
    void listener() {
      calls += 1;
    }

    focusNode.addListener(listener);
    focusNode.removeListener(listener);

    await tester.pumpWidget(
      Focus(focusNode: focusNode, child: const SizedBox()),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(calls, 0);
  });

  test('uses workspace-relative paths in the editor file bar', () {
    final workspace = _workspace();

    expect(
      workspaceEditorDisplayPath(
        workspace: workspace,
        filePath: 'src/main.dart',
      ),
      'src/main.dart',
    );
    expect(
      workspaceEditorDisplayPath(
        workspace: workspace,
        filePath: '/repo/alera/src/main.dart',
      ),
      'src/main.dart',
    );
  });

  test('includes syntax theme in the CodeForge widget key', () {
    final aleraKey = workspaceEditorCodeForgeKey(
      tabId: 'tab-1',
      filePath: 'lib/main.dart',
      themeName: EditorSyntaxThemeNames.alera,
    );
    final monokaiKey = workspaceEditorCodeForgeKey(
      tabId: 'tab-1',
      filePath: 'lib/main.dart',
      themeName: EditorSyntaxThemeNames.monokai,
    );

    expect(aleraKey, isNot(monokaiKey));
  });
}

Workspace _workspace() {
  final now = DateTime(2026, 6, 6);
  return Workspace(
    id: 'ws-1',
    projectId: 'project-1',
    name: 'alera',
    path: '/repo/alera',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}
