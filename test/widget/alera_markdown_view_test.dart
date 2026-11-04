import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/markdown/alera_code_block.dart';
import 'package:alera/src/design_system/markdown/alera_markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAleraDarkTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('renders headings and paragraph text', (tester) async {
    await tester.pumpWidget(
      _app(
        const AleraMarkdownView(
          data:
              '# Release Notes\n\n'
              'Alera keeps agents in one place.\n\n'
              '## Details\n\n'
              '- First item\n'
              '- Second item\n',
        ),
      ),
    );

    expect(find.text('Release Notes'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(
      find.textContaining('Alera keeps agents in one place.'),
      findsWidgets,
    );
    expect(find.textContaining('Second item'), findsWidgets);
  });

  testWidgets('renders fenced code through AleraCodeBlock by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AleraMarkdownView(
          data: 'Run this:\n\n```dart\nvoid main() {}\n```\n',
        ),
      ),
    );

    final block = tester.widget<AleraCodeBlock>(find.byType(AleraCodeBlock));
    expect(block.language, 'dart');
    expect(block.code, 'void main() {}');
    expect(find.text('void main() {}'), findsOneWidget);
  });

  testWidgets('uses a custom code builder when given', (tester) async {
    await tester.pumpWidget(
      _app(
        AleraMarkdownView(
          data: '```sh title=setup\nmake app-debug\n```',
          codeBuilder: (context, language, code, closed) =>
              Text('custom $language $code $closed'),
        ),
      ),
    );

    expect(find.text('custom sh make app-debug true'), findsOneWidget);
    expect(find.byType(AleraCodeBlock), findsNothing);
  });

  testWidgets('does not re-parse when rebuilt with the same text', (
    tester,
  ) async {
    var codeBuilds = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return AleraMarkdownView(
              data: '```sh\nmake app-debug\n```',
              codeBuilder: (context, language, code, closed) {
                codeBuilds += 1;
                return Text(code);
              },
            );
          },
        ),
      ),
    );
    expect(codeBuilds, 1);

    rebuild(() {});
    await tester.pump();
    expect(codeBuilds, 1);
  });

  testWidgets('reports link taps with the URL', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      _app(
        AleraMarkdownView(
          data: 'Read the [docs](https://example.com/docs) first.',
          onLinkTap: taps.add,
        ),
      ),
    );

    await tester.tap(find.text('docs'));
    expect(taps, <String>['https://example.com/docs']);
  });

  testWidgets('draws images as a placeholder without a builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AleraMarkdownView(
          data: 'Diagram: ![flow](https://example.com/flow.png)',
        ),
      ),
    );

    expect(find.byIcon(AleraIcons.viewImage), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('lets a caller selection copy code without its header', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(
        const SelectionArea(
          child: AleraMarkdownView(
            data: 'Run this:\n\n```dart\nvoid main() {}\n```\n\nThen rebuild.',
          ),
        ),
      ),
    );
    // The code scroll view's selection container joins the area a frame later.
    await tester.pump();

    final insideArea = tester.element(find.byType(AleraMarkdownView));
    Actions.invoke(
      insideArea,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    Actions.invoke(insideArea, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(copied, <String>['Run this:\n\nvoid main() {}\n\nThen rebuild.']);
  });
}
