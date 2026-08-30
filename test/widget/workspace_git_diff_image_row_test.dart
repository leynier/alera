import 'dart:typed_data';

import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_surface.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

import '../unit/fake_git_backend.dart';

late Uint8List _pngBytes;

void main() {
  setUpAll(() {
    _pngBytes = Uint8List.fromList(
      image_lib.encodePng(image_lib.Image(width: 1, height: 1)),
    );
  });

  testWidgets('binary image diff renders before and after sides', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'assets/logo.png',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[],
            isBinary: true,
          ),
        ],
      )
      ..diffBlobBytesBySide[(filePath: 'assets/logo.png', oldSide: true)] =
          _pngBytes
      ..diffBlobBytesBySide[(filePath: 'assets/logo.png', oldSide: false)] =
          _pngBytes;

    await _pumpDiffSurface(
      tester,
      backend: backend,
      filePath: 'assets/logo.png',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Before'), findsOneWidget);
    expect(find.textContaining('After'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('Binary file diff is not shown.'), findsNothing);

    final sideCalls = backend.calls
        .where((call) => call.method == 'diffBlobBytes')
        .toList();
    expect(sideCalls, hasLength(2));
    expect(
      sideCalls.map((call) => call.args['oldSide']),
      containsAll(<bool>[true, false]),
    );
    expect(
      sideCalls.every((call) => call.args['area'] == GitChangeArea.unstaged),
      isTrue,
    );
  });

  testWidgets('added image shows a placeholder for the missing old side', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'assets/new.png',
            area: .untracked,
            status: .untracked,
            lines: <GitDiffLine>[],
            isBinary: true,
          ),
        ],
      )
      ..diffBlobBytesBySide[(filePath: 'assets/new.png', oldSide: false)] =
          _pngBytes;

    await _pumpDiffSurface(
      tester,
      backend: backend,
      filePath: 'assets/new.png',
      area: .untracked,
    );
    await tester.pumpAndSettle();

    expect(find.text('Added'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('deleted image shows a placeholder for the missing new side', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'assets/gone.png',
            area: .staged,
            status: .deleted,
            lines: <GitDiffLine>[],
            isBinary: true,
          ),
        ],
      )
      ..diffBlobBytesBySide[(filePath: 'assets/gone.png', oldSide: true)] =
          _pngBytes;

    await _pumpDiffSurface(
      tester,
      backend: backend,
      filePath: 'assets/gone.png',
      area: .staged,
    );
    await tester.pumpAndSettle();

    expect(find.text('Deleted'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('non-image binaries keep the binary banner', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'assets/blob.bin',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[],
            isBinary: true,
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      filePath: 'assets/blob.bin',
    );
    await tester.pumpAndSettle();

    expect(find.text('Binary file diff is not shown.'), findsOneWidget);
    expect(
      backend.calls.where((call) => call.method == 'diffBlobBytes'),
      isEmpty,
    );
  });

  testWidgets('commit image diffs request bytes by commit instead of area', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitCommitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'assets/logo.png',
            area: .staged,
            status: .modified,
            lines: <GitDiffLine>[],
            isBinary: true,
          ),
        ],
      )
      ..diffBlobBytesBySide[(filePath: 'assets/logo.png', oldSide: true)] =
          _pngBytes
      ..diffBlobBytesBySide[(filePath: 'assets/logo.png', oldSide: false)] =
          _pngBytes;

    await _pumpDiffSurface(
      tester,
      backend: backend,
      filePath: 'assets/logo.png',
      source: .commit,
      commitOid: 'abc123',
      parentOid: 'def456',
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    final sideCalls = backend.calls
        .where((call) => call.method == 'diffBlobBytes')
        .toList();
    expect(sideCalls, hasLength(2));
    for (final call in sideCalls) {
      expect(call.args['area'], isNull);
      expect(call.args['commitOid'], 'abc123');
      expect(call.args['parentOid'], 'def456');
    }
  });
}

Future<void> _pumpDiffSurface(
  WidgetTester tester, {
  required FakeGitBackend backend,
  required String filePath,
  GitChangeArea? area = GitChangeArea.unstaged,
  WorkspaceGitDiffSource source = WorkspaceGitDiffSource.workingTree,
  String? commitOid,
  String? parentOid,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [gitBackendProvider.overrideWithValue(backend)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: WorkspaceGitDiffSurface(
              workspace: _workspace(),
              tab: _diffTab(
                filePath: filePath,
                area: area,
                source: source,
                commitOid: commitOid,
                parentOid: parentOid,
              ),
            ),
          ),
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
    path: '/tmp/project',
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
}

WorkspaceTabRecord _diffTab({
  required String filePath,
  GitChangeArea? area,
  WorkspaceGitDiffSource source = WorkspaceGitDiffSource.workingTree,
  String? commitOid,
  String? parentOid,
}) {
  final now = DateTime.utc(2026, 6, 6);
  final payload = <String, Object?>{
    workspaceTabGitDiffSourcePayloadKey: source.key,
    workspaceTabGitDiffScopePayloadKey: WorkspaceGitDiffScope.file.key,
    workspaceTabFilePathPayloadKey: filePath,
  };
  if (area != null) {
    payload[workspaceTabGitDiffAreaPayloadKey] = area.key;
  }
  if (commitOid != null) {
    payload[workspaceTabGitDiffCommitOidPayloadKey] = commitOid;
  }
  if (parentOid != null) {
    payload[workspaceTabGitDiffParentOidPayloadKey] = parentOid;
  }
  return WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: 'workspace-1',
    kind: .gitDiff,
    title: 'diff',
    payload: payload,
    createdAt: now,
    updatedAt: now,
  );
}
