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
    expect(find.byTooltip('Add project'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell && widget.mouseCursor == SystemMouseCursors.click,
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.byTooltip('Add project'));

    expect(addProjectTaps, 1);
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

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 52, child: child)),
    );
  }
}
