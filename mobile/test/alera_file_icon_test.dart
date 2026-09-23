import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.preview.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

class _FixedSourceControlController extends SourceControlController {
  @override
  Future<MobileGitStatusSnapshot> build(String hostId, String workspaceId) =>
      Future.value(
        const MobileGitStatusSnapshot(
          isRepository: true,
          branch: 'main',
          entries: <MobileGitChange>[
            MobileGitChange(
              path: 'lib/src/main.dart',
              area: 'unstaged',
              status: 'modified',
              added: 3,
              removed: 1,
            ),
          ],
        ),
      );
}

void main() {
  group('AleraFileIconKind.fromEntryKind', () {
    test('maps runtime entry kinds like the desktop explorer', () {
      expect(
        AleraFileIconKind.fromEntryKind('directory'),
        AleraFileIconKind.folder,
      );
      expect(AleraFileIconKind.fromEntryKind('file'), AleraFileIconKind.file);
      expect(
        AleraFileIconKind.fromEntryKind('symlink'),
        AleraFileIconKind.symlink,
      );
      expect(
        AleraFileIconKind.fromEntryKind('other'),
        AleraFileIconKind.generic,
      );
      expect(
        AleraFileIconKind.fromEntryKind('socket'),
        AleraFileIconKind.generic,
      );
    });
  });

  test('matches the lowercase basename of POSIX and Windows paths', () {
    expect(aleraFileIconName('lib/src/Main.DART'), 'main.dart');
    expect(aleraFileIconName(r'rust\src\lib.rs'), 'lib.rs');
    expect(aleraFileIconName('Makefile'), 'makefile');
  });

  testWidgets('files and folders render the icon theme glyph at the size', (
    tester,
  ) async {
    await _pump(
      tester,
      const Row(
        mainAxisSize: .min,
        children: <Widget>[
          AleraFileIcon(pathOrName: 'lib/main.dart', kind: .file, size: 20),
          AleraFileIcon(pathOrName: 'src', kind: .folder, size: 20),
          AleraFileIcon(
            pathOrName: 'src',
            kind: .folder,
            isExpanded: true,
            size: 20,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(3));
    for (final element in find.byType(AleraFileIcon).evaluate()) {
      expect(tester.getSize(find.byWidget(element.widget)), const Size(20, 20));
    }
    final folders = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .skip(1)
        .map((picture) => picture.bytesLoader)
        .toList();
    expect(folders[0], isNot(folders[1]));
  });

  testWidgets('symlinks and other entries use the Alera fallback glyphs', (
    tester,
  ) async {
    await _pump(
      tester,
      const Row(
        mainAxisSize: .min,
        children: <Widget>[
          AleraFileIcon(pathOrName: 'current', kind: .symlink),
          AleraFileIcon(pathOrName: 'fifo', kind: .generic),
        ],
      ),
    );

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byIcon(AleraIcons.link), findsOneWidget);
    expect(find.byIcon(AleraIcons.fileGeneric), findsOneWidget);
  });

  testWidgets('previews lay out without exceptions', (tester) async {
    await _pump(
      tester,
      Column(
        children: <Widget>[
          aleraFileIconFilesPreview(),
          aleraFileIconFoldersPreview(),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AleraFileIcon), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('source control rows lead with the icon and trail the status', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceControlControllerProvider(
            'host-1',
            'workspace-1',
          ).overrideWith(_FixedSourceControlController.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SourceControlPanel(
              hostId: 'host-1',
              workspaceId: 'workspace-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.byType(AleraFileIcon),
      matching: find.byType(InkWell),
    );
    Offset centerOf(Finder finder) =>
        tester.getCenter(find.descendant(of: row.first, matching: finder));
    final icon = centerOf(find.byType(AleraFileIcon));
    final name = centerOf(find.text('main.dart'));
    final status = centerOf(find.text('M'));
    final added = centerOf(find.text('+3'));
    expect(icon.dx, lessThan(name.dx));
    expect(name.dx, lessThan(status.dx));
    expect(status.dx, lessThan(added.dx));
  });
}
