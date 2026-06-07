import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_image_preview_surface.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('cache key changes when resolved image metadata changes', () {
    const first = ResolvedWorkspaceFile(
      path: '/repo/alera/logo.png',
      modifiedMicros: 1,
      length: 12,
    );
    const second = ResolvedWorkspaceFile(
      path: '/repo/alera/logo.png',
      modifiedMicros: 2,
      length: 12,
    );

    expect(
      workspaceImagePreviewCacheKeyForTesting(first),
      isNot(workspaceImagePreviewCacheKeyForTesting(second)),
    );
  });

  test('uses opened path to choose ico decoding for symlinked files', () {
    expect(
      workspaceImagePreviewUsesIcoDecoderForTesting('assets/favicon.ico'),
      isTrue,
    );
    expect(
      workspaceImagePreviewUsesIcoDecoderForTesting(
        'assets/favicon-target.bin',
      ),
      isFalse,
    );
  });

  test('decodes ico bytes into png bytes for the Flutter image codec', () {
    final icon = image_lib.Image(width: 2, height: 2);
    icon.setPixelRgba(0, 0, 255, 0, 0, 255);
    icon.setPixelRgba(1, 0, 0, 255, 0, 255);
    icon.setPixelRgba(0, 1, 0, 0, 255, 255);
    icon.setPixelRgba(1, 1, 255, 255, 255, 255);
    final icoBytes = image_lib.encodeIco(icon, singleFrame: true);

    final pngBytes = workspaceImagePreviewDecodeIcoToPngBytesForTesting(
      icoBytes,
    );

    final decodedPng = image_lib.decodePng(pngBytes);
    expect(decodedPng, isNotNull);
    expect(decodedPng!.width, 2);
    expect(decodedPng.height, 2);
  });

  test('decodes png-backed ico files into png bytes', () {
    final favicon = image_lib.Image(width: 32, height: 32);
    favicon.setPixelRgba(0, 0, 0, 128, 255, 255);
    final pngBackedIcoBytes = image_lib.encodePng(favicon);

    final pngBytes = workspaceImagePreviewDecodeIcoToPngBytesForTesting(
      pngBackedIcoBytes,
    );

    final decodedPng = image_lib.decodePng(pngBytes);
    expect(decodedPng, isNotNull);
    expect(decodedPng!.width, 32);
    expect(decodedPng.height, 32);
  });

  test('selects the largest frame from multi-size ico files', () {
    final smallIcon = image_lib.Image(width: 16, height: 16);
    smallIcon.setPixelRgba(0, 0, 255, 0, 0, 255);
    final largeIcon = image_lib.Image(width: 32, height: 32);
    largeIcon.setPixelRgba(0, 0, 0, 255, 0, 255);
    smallIcon.addFrame(largeIcon);
    final multiSizeIcoBytes = image_lib.encodeIco(smallIcon);

    final pngBytes = workspaceImagePreviewDecodeIcoToPngBytesForTesting(
      multiSizeIcoBytes,
    );

    final decodedPng = image_lib.decodePng(pngBytes);
    expect(decodedPng, isNotNull);
    expect(decodedPng!.width, 32);
    expect(decodedPng.height, 32);
  });

  test('treats zero-sized ico directory entries as 256 pixels', () {
    final smallIcon = image_lib.Image(width: 16, height: 16);
    smallIcon.setPixelRgba(0, 0, 255, 0, 0, 255);
    final mediumIcon = image_lib.Image(width: 32, height: 32);
    mediumIcon.setPixelRgba(0, 0, 0, 255, 0, 255);
    final largeIcon = image_lib.Image(width: 256, height: 256);
    largeIcon.setPixelRgba(0, 0, 0, 0, 255, 255);
    smallIcon
      ..addFrame(mediumIcon)
      ..addFrame(largeIcon);
    final multiSizeIcoBytes = image_lib.encodeIco(smallIcon);

    final pngBytes = workspaceImagePreviewDecodeIcoToPngBytesForTesting(
      multiSizeIcoBytes,
    );

    final decodedPng = image_lib.decodePng(pngBytes);
    expect(decodedPng, isNotNull);
    expect(decodedPng!.width, 256);
    expect(decodedPng.height, 256);
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
          home: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (hasFocus) {
              paneFocused = hasFocus;
            },
            child: WorkspaceImagePreviewSurface(
              workspace: _workspace(),
              tab: _tab('tab-image', 'image.png'),
              autofocus: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(paneFocused, isFalse);

    await tester.tap(find.byType(WorkspaceImagePreviewSurface));
    await tester.pump();

    expect(paneFocused, isTrue);
  });

  testWidgets('uses a hand cursor over the resolved image', (tester) async {
    const file = ResolvedWorkspaceFile(
      path: '/repo/alera/logo.png',
      modifiedMicros: 1,
      length: 12,
    );

    await tester.pumpWidget(
      _previewHarness(
        service: _ResolvedWorkspaceFileService(file),
        tab: _tab('tab-image', 'logo.png'),
      ),
    );
    await tester.pump();
    await tester.pump();

    final image = find.byKey(workspaceImagePreviewCacheKeyForTesting(file));
    final handCursor = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion && widget.cursor == SystemMouseCursors.click,
    );

    expect(image, findsOneWidget);
    expect(find.ancestor(of: image, matching: handCursor), findsOneWidget);
  });

  testWidgets('ignores stale load completions after tab changes', (
    tester,
  ) async {
    final oldLoadGate = Completer<void>();
    final service = _StaleLoadWorkspaceFileService(oldLoadGate);

    await tester.pumpWidget(
      _previewHarness(service: service, tab: _tab('tab-old', 'old.png')),
    );
    await tester.pump();

    await tester.pumpWidget(
      _previewHarness(service: service, tab: _tab('tab-new', 'new.png')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Image path is invalid'), findsOneWidget);

    oldLoadGate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Image path is invalid'), findsOneWidget);
    expect(find.text('Image is outside the workspace'), findsNothing);
  });
}

Widget _previewHarness({
  required WorkspaceFileService service,
  required WorkspaceTabRecord tab,
}) {
  return ProviderScope(
    overrides: [workspaceFileServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      home: WorkspaceImagePreviewSurface(
        workspace: _workspace(),
        tab: tab,
        autofocus: false,
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
    kind: WorkspaceTabKind.editor,
    payload: <String, Object?>{workspaceTabFilePathPayloadKey: filePath},
    createdAt: now,
    updatedAt: now,
  );
}

class _ResolvedWorkspaceFileService extends WorkspaceFileService {
  const _ResolvedWorkspaceFileService(this.file);

  final ResolvedWorkspaceFile file;

  @override
  Future<ResolvedWorkspaceFile> resolveWorkspaceFilePath({
    required String workspacePath,
    required String relativePath,
  }) async {
    return file;
  }
}

class _ImmediateErrorWorkspaceFileService extends WorkspaceFileService {
  @override
  Future<ResolvedWorkspaceFile> resolveWorkspaceFilePath({
    required String workspacePath,
    required String relativePath,
  }) async {
    throw const native.WorkspaceFileError(
      kind: native.WorkspaceFileErrorKind.invalidPath,
      context: 'image.png',
    );
  }
}

class _StaleLoadWorkspaceFileService extends WorkspaceFileService {
  _StaleLoadWorkspaceFileService(this.oldLoadGate);

  final Completer<void> oldLoadGate;

  @override
  Future<ResolvedWorkspaceFile> resolveWorkspaceFilePath({
    required String workspacePath,
    required String relativePath,
  }) async {
    if (relativePath == 'old.png') {
      await oldLoadGate.future;
      throw const native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.outsideWorkspace,
        context: 'old.png',
      );
    }
    throw const native.WorkspaceFileError(
      kind: native.WorkspaceFileErrorKind.invalidPath,
      context: 'new.png',
    );
  }
}
