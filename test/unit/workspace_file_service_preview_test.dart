import 'dart:io';

import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorkspaceFileService.resolveWorkspaceFilePath', () {
    const service = WorkspaceFileService();

    test('resolves a relative file inside the workspace', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'alera_preview_workspace_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final file = File(p.join(workspace.path, 'assets', 'logo.png'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3]);

      final resolved = await service.resolveWorkspaceFilePath(
        workspacePath: workspace.path,
        relativePath: 'assets/logo.png',
      );

      expect(
        p.equals(resolved.path, await file.resolveSymbolicLinks()),
        isTrue,
      );
      expect(resolved.length, 3);
      expect(resolved.modifiedMicros, greaterThan(0));
    });

    test('preserves whitespace in relative file components', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'alera_preview_workspace_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final file = File(p.join(workspace.path, 'assets', ' logo.png '));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3]);

      final resolved = await service.resolveWorkspaceFilePath(
        workspacePath: workspace.path,
        relativePath: 'assets/ logo.png ',
      );

      expect(
        p.equals(resolved.path, await file.resolveSymbolicLinks()),
        isTrue,
      );
    });

    test('rejects traversal paths before touching the filesystem', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'alera_preview_workspace_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      await expectLater(
        service.resolveWorkspaceFilePath(
          workspacePath: workspace.path,
          relativePath: '../outside.png',
        ),
        throwsA(
          isA<native.WorkspaceFileError>().having(
            (error) => error.kind,
            'kind',
            native.WorkspaceFileErrorKind.invalidPath,
          ),
        ),
      );
    });

    test('rejects symlinks that escape the workspace', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'alera_preview_workspace_',
      );
      final outside = await Directory.systemTemp.createTemp(
        'alera_preview_outside_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final outsideFile = File(p.join(outside.path, 'secret.png'));
      await outsideFile.writeAsBytes(<int>[1, 2, 3]);

      final link = Link(p.join(workspace.path, 'linked.png'));
      try {
        await link.create(outsideFile.path);
      } on FileSystemException {
        markTestSkipped('Symlink creation is not available on this platform.');
        return;
      }

      await expectLater(
        service.resolveWorkspaceFilePath(
          workspacePath: workspace.path,
          relativePath: 'linked.png',
        ),
        throwsA(
          isA<native.WorkspaceFileError>().having(
            (error) => error.kind,
            'kind',
            native.WorkspaceFileErrorKind.outsideWorkspace,
          ),
        ),
      );
    });
  });
}
