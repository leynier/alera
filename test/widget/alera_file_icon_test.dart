import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vscode_material_icon_theme/vscode_material_icon_theme.dart';

void main() {
  testWidgets('renders vscode material icons for files', (tester) async {
    await _pumpIcon(
      tester,
      const AleraFileIcon(
        pathOrName: 'docs/README.md',
        kind: AleraFileIconKind.file,
      ),
    );

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.bytesLoader, fileToIcon('readme.md'));
  });

  testWidgets('renders vscode material icons for folders', (tester) async {
    await _pumpIcon(
      tester,
      const AleraFileIcon(
        pathOrName: 'src',
        kind: AleraFileIconKind.folder,
        isExpanded: true,
      ),
    );

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.bytesLoader, directoryToIcon('src', isExpanded: true));
  });

  testWidgets('keeps symlink and generic fallbacks as material icons', (
    tester,
  ) async {
    await _pumpIcon(
      tester,
      const Row(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          AleraFileIcon(pathOrName: 'linked', kind: AleraFileIconKind.symlink),
          AleraFileIcon(pathOrName: '', kind: AleraFileIconKind.generic),
        ],
      ),
    );

    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });
}

Future<void> _pumpIcon(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: child),
  );
}
