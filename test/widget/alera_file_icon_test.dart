import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vscode_material_icon_theme/vscode_material_icon_theme.dart';

void main() {
  testWidgets('renders vscode material icons for files', (tester) async {
    await _pumpIcon(
      tester,
      const AleraFileIcon(pathOrName: 'docs/README.md', kind: .file),
    );

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.bytesLoader, fileToIcon('readme.md'));
  });

  testWidgets('renders vscode material icons for folders', (tester) async {
    await _pumpIcon(
      tester,
      const AleraFileIcon(pathOrName: 'src', kind: .folder, isExpanded: true),
    );

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.bytesLoader, directoryToIcon('src', isExpanded: true));
  });

  testWidgets('keeps symlink and generic fallbacks as lucide icons', (
    tester,
  ) async {
    await _pumpIcon(
      tester,
      const Row(
        textDirection: .ltr,
        children: <Widget>[
          AleraFileIcon(pathOrName: 'linked', kind: .symlink),
          AleraFileIcon(pathOrName: '', kind: .generic),
        ],
      ),
    );

    expect(find.byIcon(AleraIcons.link), findsOneWidget);
    expect(find.byIcon(AleraIcons.fileGeneric), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });
}

Future<void> _pumpIcon(WidgetTester tester, Widget child) {
  return tester.pumpWidget(Directionality(textDirection: .ltr, child: child));
}
