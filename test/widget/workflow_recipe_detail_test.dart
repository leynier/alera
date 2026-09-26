import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_recipe_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'compact scaled recipe exposes origin-specific actions without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = TextEditingController(text: '{}');
      final filename = TextEditingController();
      addTearDown(document.dispose);
      addTearDown(filename.dispose);
      var copied = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAleraDarkTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: WorkflowRecipeDetail(
                record: const {
                  'source': {'origin': 'builtIn'},
                  'recipe': {
                    'name': 'Feature Delivery',
                    'description': 'Review a foundation and product.',
                    'revision': 1,
                    'stages': [],
                    'contracts': [],
                  },
                },
                document: document,
                filename: filename,
                editing: false,
                exporting: false,
                busy: false,
                preview: null,
                onEdit: () {},
                onCopy: () => copied = true,
                onValidate: () {},
                onSave: () {},
                onCancel: () {},
                onExport: null,
                onPreview: null,
                onApply: null,
                onFilenameChanged: (_) {},
                onOpen: null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Edit Personal'), findsNothing);
      expect(find.textContaining('Built-in'), findsOneWidget);
      await tester.tap(find.text('Copy To Personal'));
      expect(copied, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
