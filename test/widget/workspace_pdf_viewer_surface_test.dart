import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_pdf_viewer_surface.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache key changes when resolved PDF metadata changes', () {
    const first = ResolvedWorkspaceFile(
      path: '/repo/alera/spec.pdf',
      modifiedMicros: 1,
      length: 12,
    );
    const second = ResolvedWorkspaceFile(
      path: '/repo/alera/spec.pdf',
      modifiedMicros: 2,
      length: 12,
    );

    expect(
      workspacePdfViewerCacheKeyForTesting(first),
      isNot(workspacePdfViewerCacheKeyForTesting(second)),
    );
  });

  testWidgets('requests focus when clicked so the parent pane activates', (
    tester,
  ) async {
    var paneFocused = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceFileServiceProvider.overrideWithValue(
            _ImmediateErrorWorkspaceFileService(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                paneFocused = hasFocus;
              },
              child: WorkspacePdfViewerSurface(
                workspace: _workspace(),
                tab: _tab('tab-pdf', 'guide.pdf'),
                autofocus: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(paneFocused, isFalse);

    await tester.tap(find.byType(WorkspacePdfViewerSurface));
    await tester.pump();

    expect(paneFocused, isTrue);
  });

  testWidgets('maps workspace file errors to PDF messages', (tester) async {
    await tester.pumpWidget(
      _viewerHarness(
        service: _ImmediateErrorWorkspaceFileService(),
        tab: _tab('tab-pdf', 'guide.pdf'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('PDF path is invalid'), findsOneWidget);
  });
}

Widget _viewerHarness({
  required WorkspaceFileService service,
  required WorkspaceTabRecord tab,
}) {
  return ProviderScope(
    overrides: [workspaceFileServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      home: Scaffold(
        body: WorkspacePdfViewerSurface(
          workspace: _workspace(),
          tab: tab,
          autofocus: false,
        ),
      ),
    ),
  );
}

Workspace _workspace() {
  final now = DateTime.utc(2026, 6, 6);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Main',
    path: '/repo/alera',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab(String id, String filePath) {
  final now = DateTime.utc(2026, 6, 6);
  return WorkspaceTabRecord(
    id: id,
    workspaceId: 'workspace-1',
    title: filePath,
    kind: WorkspaceTabKind.pdf,
    payload: <String, Object?>{workspaceTabFilePathPayloadKey: filePath},
    createdAt: now,
    updatedAt: now,
  );
}

class _ImmediateErrorWorkspaceFileService extends WorkspaceFileService {
  @override
  Future<ResolvedWorkspaceFile> resolveWorkspaceFilePath({
    required String workspacePath,
    required String relativePath,
  }) async {
    throw const native.WorkspaceFileError(
      kind: native.WorkspaceFileErrorKind.invalidPath,
      context: 'guide.pdf',
    );
  }
}
