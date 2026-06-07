import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_merman_viewer_surface.dart';
import 'package:alera/src/rust/api/merman_viewer.dart' as merman_native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prepares merman SVGs for flutter_svg without relying on style tags',
    () {
      final prepared = prepareMermanSvgForFlutterSvg(
        '<svg>'
        '<rect class="basic label-container" width="10" height="10"/>'
        '<path class="edge-thickness-normal flowchart-link" d="M0 0L10 10"/>'
        '<path class="arrowMarkerPath" d="M0 0L10 5L0 10z"/>'
        '<text fill="#333">Editor tab</text>'
        '</svg>',
      );

      expect(prepared, contains('fill="#242424"'));
      expect(prepared, contains('stroke="#323232"'));
      expect(prepared, contains('fill="none"'));
      expect(prepared, contains('stroke="#A1A1A1"'));
      expect(prepared, contains('fill="#F5F5F5"'));
    },
  );

  testWidgets(
    'renders merman previews and exposes editor and refresh actions',
    (tester) async {
      final service = _FakeWorkspaceFileService();
      final openedEditors = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [workspaceFileServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            home: Scaffold(
              body: WorkspaceMermanViewerSurface(
                workspace: _workspace(),
                tab: _tab(),
                autofocus: false,
                onOpenEditor: openedEditors.add,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.byTooltip('Open editor'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(service.renderCalls, 1);

      await tester.tap(find.byTooltip('Open editor'));
      expect(openedEditors, <String>['docs/diagram.mmd']);

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();
      await tester.pump();
      expect(service.renderCalls, 2);
    },
  );
}

Workspace _workspace() => Workspace(
  id: 'workspace-1',
  projectId: 'project-1',
  name: 'Main',
  branch: 'main',
  path: '/tmp/alera',
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

WorkspaceTabRecord _tab() => WorkspaceTabRecord(
  id: 'tab-1',
  workspaceId: 'workspace-1',
  title: 'diagram.mmd preview',
  kind: WorkspaceTabKind.editor,
  payload: const <String, Object?>{
    workspaceTabFilePathPayloadKey: 'docs/diagram.mmd',
    workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
  },
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
);

class _FakeWorkspaceFileService extends WorkspaceFileService {
  int renderCalls = 0;

  @override
  Future<merman_native.MermanWorkspaceRender> renderMermanWorkspaceFile({
    required String workspacePath,
    required String relativePath,
  }) async {
    renderCalls += 1;
    return merman_native.MermanWorkspaceRender(
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
      contentToken: 'token-$renderCalls',
      modifiedMillis: renderCalls,
      size: BigInt.from(10),
    );
  }
}
