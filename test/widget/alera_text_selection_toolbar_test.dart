import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_menu_item.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop selection menu matches Alera dropdown interactions', (
    tester,
  ) async {
    var copied = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme().copyWith(platform: .linux),
        home: Scaffold(
          body: AleraTextSelectionToolbar(
            anchors: const TextSelectionToolbarAnchors(
              primaryAnchor: Offset(240, 180),
            ),
            buttonItems: <ContextMenuButtonItem>[
              ContextMenuButtonItem(
                type: .copy,
                onPressed: () => copied = true,
              ),
              ContextMenuButtonItem(type: .selectAll, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AleraDropdownMenuItem), findsNWidgets(2));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AleraDropdownMenuItem).first).height,
      AleraTokens.space32 + AleraTokens.space4,
    );
    expect(
      tester
          .widgetList<InkWell>(find.byType(InkWell))
          .map((inkWell) => inkWell.mouseCursor),
      everyElement(SystemMouseCursors.click),
    );

    final menu = tester.widget<SizedBox>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == AleraTokens.contextMenuWidth,
      ),
    );
    expect(menu.width, AleraTokens.contextMenuWidth);
    final surface = tester
        .widgetList<Material>(find.byType(Material))
        .firstWhere(
          (material) =>
              material.color == AleraTokens.surface &&
              material.shape is RoundedRectangleBorder,
        );
    final shape = surface.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AleraTokens.radiusMd));
    expect(shape.side.color, AleraTokens.border);

    await tester.tap(find.text('Copy'));
    expect(copied, isTrue);
  });

  testWidgets('touch platforms retain Flutter adaptive selection toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme().copyWith(platform: .android),
        home: Scaffold(
          body: AleraTextSelectionToolbar(
            anchors: const TextSelectionToolbarAnchors(
              primaryAnchor: Offset(240, 180),
            ),
            buttonItems: <ContextMenuButtonItem>[
              ContextMenuButtonItem(type: .copy, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.byType(AleraDropdownMenuItem), findsNothing);
  });
}
