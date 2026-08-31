import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    final nameFinder = find.text(kAleraAppName);
    expect(nameFinder, findsOneWidget);
    final logoRect = tester.getRect(find.byType(Image));
    expect(logoRect.right, lessThanOrEqualTo(tester.getRect(nameFinder).left));
    expect(find.byTooltip('Add Project'), findsOneWidget);
    expect(find.byTooltip('Collapse Sidebar'), findsOneWidget);
    expect(find.byTooltip('Expand Sidebar'), findsNothing);

    final addRect = tester.getRect(find.byTooltip('Add Project'));
    final collapseRect = tester.getRect(find.byTooltip('Collapse Sidebar'));
    expect(addRect.right, lessThanOrEqualTo(collapseRect.left));

    await tester.tap(find.byTooltip('Add Project'));
    await tester.tap(find.byTooltip('Collapse Sidebar'));

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

    expect(find.text(kAleraAppName), findsNothing);
    expect(find.byTooltip('Add Project'), findsNothing);
    expect(find.byTooltip('Collapse Sidebar'), findsNothing);
    expect(find.byTooltip('Expand Sidebar'), findsOneWidget);

    final headerRect = tester.getRect(find.byType(SidebarBrandRow));
    final expandRect = tester.getRect(find.byTooltip('Expand Sidebar'));
    expect(expandRect.right, headerRect.right);

    await tester.tap(find.byTooltip('Expand Sidebar'));

    expect(addProjectTaps, 0);
    expect(expandTaps, 1);
  });
}

class const _Host({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 300, child: child)),
        ),
      ),
    );
  }
}
