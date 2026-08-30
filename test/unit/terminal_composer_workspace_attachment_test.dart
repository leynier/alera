import 'package:alera/src/features/workbench/application/terminal_composer_workspace_attachment.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('opens supported workspace text files inside Alera', () async {
    final files = _FakeWorkspaceFileService();
    final opened = <String>[];
    final workspacePath = p.absolute('workspace');

    final handled = await openTerminalComposerWorkspaceAttachment(
      workspacePath: workspacePath,
      filePath: p.join(workspacePath, 'lib', 'main.dart'),
      workspaceFiles: files,
      openFile: (relativePath) async => opened.add(relativePath),
    );

    expect(handled, isTrue);
    expect(files.readTextPaths, <String>[p.join('lib', 'main.dart')]);
    expect(files.resolvedPaths, isEmpty);
    expect(opened, <String>[p.join('lib', 'main.dart')]);
  });

  test('resolves supported workspace previews before opening them', () async {
    final files = _FakeWorkspaceFileService();
    final opened = <String>[];
    final workspacePath = p.absolute('workspace');

    final handled = await openTerminalComposerWorkspaceAttachment(
      workspacePath: workspacePath,
      filePath: p.join(workspacePath, 'assets', 'image.png'),
      workspaceFiles: files,
      openFile: (relativePath) async => opened.add(relativePath),
    );

    expect(handled, isTrue);
    expect(files.resolvedPaths, <String>[p.join('assets', 'image.png')]);
    expect(files.readTextPaths, isEmpty);
    expect(opened, <String>[p.join('assets', 'image.png')]);
  });

  test('leaves outside and unsupported files to the system launcher', () async {
    final files = _FakeWorkspaceFileService(unsupportedText: true);
    final opened = <String>[];
    final workspacePath = p.absolute('workspace');

    final outside = await openTerminalComposerWorkspaceAttachment(
      workspacePath: workspacePath,
      filePath: p.join(p.dirname(workspacePath), 'elsewhere', 'report.txt'),
      workspaceFiles: files,
      openFile: (relativePath) async => opened.add(relativePath),
    );
    final unsupported = await openTerminalComposerWorkspaceAttachment(
      workspacePath: workspacePath,
      filePath: p.join(workspacePath, 'archive.bin'),
      workspaceFiles: files,
      openFile: (relativePath) async => opened.add(relativePath),
    );

    expect(outside, isFalse);
    expect(unsupported, isFalse);
    expect(opened, isEmpty);
  });
}

class _FakeWorkspaceFileService({final bool unsupportedText = false})
    extends WorkspaceFileService {
  final List<String> readTextPaths = <String>[];
  final List<String> resolvedPaths = <String>[];

  @override
  Future<native.WorkspaceTextFile> readTextFile({
    required String workspacePath,
    required String relativePath,
  }) async {
    readTextPaths.add(relativePath);
    if (unsupportedText) {
      throw const native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.unsupported,
        context: 'binary file',
      );
    }
    return native.WorkspaceTextFile(
      content: 'text',
      contentToken: 'token',
      modifiedMillis: 0,
      size: .from(4),
    );
  }

  @override
  Future<ResolvedWorkspaceFile> resolveWorkspaceFilePath({
    required String workspacePath,
    required String relativePath,
  }) async {
    resolvedPaths.add(relativePath);
    return ResolvedWorkspaceFile(
      path: p.join(workspacePath, relativePath),
      modifiedMicros: 0,
      length: 1,
    );
  }
}
