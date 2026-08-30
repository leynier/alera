import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.preview.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, buildPreview) in [
    ('Rename Host', aleraRenameDialogPreview),
    ('New Terminal', aleraActionSheetPreview),
  ]) {
    testWidgets('$name preview lays out within its phone viewport', (
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
                  preview.wrapper!(buildPreview()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preview applies the dark Alera theme and Inter typography', (
    tester,
  ) async {
    const preview = AleraPreview();
    late ThemeData theme;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => preview.theme!().apply(
            context,
            Builder(
              builder: (context) {
                theme = Theme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(preview.brightness, Brightness.dark);
    expect(theme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
  });
}
