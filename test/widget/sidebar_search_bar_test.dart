import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search input uses fixed taller height and rounded borders', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: SidebarSearchBar(
              initialQuery: '',
              focusNode: focusNode,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final textField = tester.widget<TextField>(find.byType(TextField));
    final decoration = textField.decoration!;
    final border = decoration.border! as OutlineInputBorder;
    final enabledBorder = decoration.enabledBorder! as OutlineInputBorder;
    final focusedBorder = decoration.focusedBorder! as OutlineInputBorder;

    expect(
      decoration.contentPadding,
      const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
    );
    expect(border.borderRadius, BorderRadius.circular(AleraTokens.radiusLg));
    expect(
      enabledBorder.borderRadius,
      BorderRadius.circular(AleraTokens.radiusLg),
    );
    expect(
      focusedBorder.borderRadius,
      BorderRadius.circular(AleraTokens.radiusLg),
    );
    expect(
      tester.getSize(find.byType(TextField)).height,
      AleraTokens.space32 + AleraTokens.space8,
    );
  });
}
