import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_collapsed_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsed rail keeps project navigation and add project', (
    tester,
  ) async {
    var addProjectTaps = 0;

    await tester.pumpWidget(
      _Host(
        child: SidebarCollapsedRail(
          projects: <Project>[_project()],
          activeProjectId: null,
          workspaceCountByProject: const <String, int>{},
          onSelectProject: (_) {},
          onAddProject: () => addProjectTaps++,
        ),
      ),
    );

    expect(find.byTooltip('Add a project first'), findsNothing);
    expect(find.byTooltip('Add Project'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell && widget.mouseCursor == SystemMouseCursors.click,
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.byTooltip('Add Project'));

    expect(addProjectTaps, 1);
  });

  testWidgets('project avatars highlight on pointer hover', (tester) async {
    await tester.pumpWidget(
      _Host(
        child: SidebarCollapsedRail(
          projects: <Project>[_project()],
          activeProjectId: null,
          workspaceCountByProject: const <String, int>{},
          onSelectProject: (_) {},
          onAddProject: () {},
        ),
      ),
    );

    final avatarFinder = find.ancestor(
      of: find.text('O'),
      matching: find.byType(AnimatedContainer),
    );
    BoxDecoration decorationOf() =>
        tester.widget<AnimatedContainer>(avatarFinder.first).decoration!
            as BoxDecoration;

    expect(decorationOf().color, Colors.transparent);

    final mouse = await tester.createGesture(kind: .mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: .zero);
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.text('O')));
    await tester.pumpAndSettle();
    expect(decorationOf().color, isNot(Colors.transparent));

    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(decorationOf().color, Colors.transparent);
  });
}

Project _project() {
  final now = DateTime(2026, 5, 16);
  return Project(
    id: 'project-1',
    name: 'orca',
    repoPath: '/repo/orca',
    createdAt: now,
    updatedAt: now,
  );
}

class const _Host({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 52, child: child)),
    );
  }
}
