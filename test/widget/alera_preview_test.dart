import 'package:alera/src/design_system/alera_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preview applies the dark Alera theme and Inter typography', (
    tester,
  ) async {
    const preview = AleraPreview();
    late ThemeData theme;
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
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
