import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expanded header shows add project before collapse action', (
    tester,
  ) async {
    var addProjectTaps = 0;
    var collapseTaps = 0;

    await tester.pumpWidget(
      _Host(
        child: SidebarBrandRow(
          collapsed: false,
          onAddProject: () => addProjectTaps++,
          onToggleCollapsed: () => collapseTaps++,
        ),
      ),
    );

    expect(find.text('Alera'), findsOneWidget);
    expect(find.byTooltip('Add project'), findsOneWidget);
    expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
    expect(find.byTooltip('Expand sidebar'), findsNothing);

    final addRect = tester.getRect(find.byTooltip('Add project'));
    final collapseRect = tester.getRect(find.byTooltip('Collapse sidebar'));
    expect(addRect.right, lessThanOrEqualTo(collapseRect.left));

    await tester.tap(find.byTooltip('Add project'));
    await tester.tap(find.byTooltip('Collapse sidebar'));

    expect(addProjectTaps, 1);
    expect(collapseTaps, 1);
  });

  testWidgets('collapsed header only shows expand action', (tester) async {
    var addProjectTaps = 0;
    var expandTaps = 0;

    await tester.pumpWidget(
      _Host(
        child: SidebarBrandRow(
          collapsed: true,
          onAddProject: () => addProjectTaps++,
          onToggleCollapsed: () => expandTaps++,
        ),
      ),
    );

    expect(find.text('Alera'), findsNothing);
    expect(find.byTooltip('Add project'), findsNothing);
    expect(find.byTooltip('Collapse sidebar'), findsNothing);
    expect(find.byTooltip('Expand sidebar'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand sidebar'));

    expect(addProjectTaps, 0);
    expect(expandTaps, 1);
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    );
  }
}
