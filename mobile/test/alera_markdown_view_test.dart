import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Markdown View preview renders within its phone viewport', (
    tester,
  ) async {
    const preview = AleraPreview();
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: UnconstrainedBox(
          child: SizedBox.fromSize(
            size: preview.size,
            child: Builder(
              builder: (context) => preview.theme!().apply(
                context,
                preview.wrapper!(aleraMarkdownViewPreview()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AleraMarkdownView), findsOneWidget);
    expect(
      find.textContaining('Workspace Guide', findRichText: true),
      findsWidgets,
    );
    expect(find.textContaining('# Workspace Guide'), findsNothing);
    expect(
      find.textContaining("print('Hello from Alera')", findRichText: true),
      findsWidgets,
    );
  });
}
