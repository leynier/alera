import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspaceFilePreviewKindForPath', () {
    test('classifies supported image extensions as images', () {
      expect(
        workspaceFilePreviewKindForPath('assets/logo.PNG'),
        WorkspaceFilePreviewKind.image,
      );
      expect(
        workspaceFilePreviewKindForPath('docs/screenshots/app.jpeg'),
        WorkspaceFilePreviewKind.image,
      );
      expect(
        workspaceFilePreviewKindForPath('windows/app-icon.ico'),
        WorkspaceFilePreviewKind.image,
      );
    });

    test('keeps non-image extensions as text', () {
      expect(
        workspaceFilePreviewKindForPath('lib/main.dart'),
        WorkspaceFilePreviewKind.text,
      );
      expect(
        workspaceFilePreviewKindForPath('readme.md'),
        WorkspaceFilePreviewKind.text,
      );
      expect(
        workspaceFilePreviewKindForPath('icons/alera.svg'),
        WorkspaceFilePreviewKind.text,
      );
    });

    test('classifies PDF extensions as PDF previews', () {
      expect(
        workspaceFilePreviewKindForPath('docs/spec.pdf'),
        WorkspaceFilePreviewKind.pdf,
      );
      expect(
        workspaceFilePreviewKindForPath('docs/WHITEPAPER.PDF'),
        WorkspaceFilePreviewKind.pdf,
      );
      expect(isWorkspacePdfFilePath('docs/spec.pdf'), isTrue);
    });
  });
}
