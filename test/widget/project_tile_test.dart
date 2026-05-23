import 'dart:ui';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/widgets/project_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('project row uses click cursor and toggles on tap', (
    tester,
  ) async {
    var toggles = 0;

    await tester.pumpWidget(
      _Host(
        child: ProjectTile(
          project: _project(),
          expanded: false,
          chatCount: 2,
          onToggle: () => toggles++,
          onNewChat: () {},
          onRemoveProject: () {},
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell && widget.mouseCursor == SystemMouseCursors.click,
      ),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.more_horiz),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('orca'));

    expect(toggles, 1);
  });

  testWidgets('project row hover surface uses common project radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(
        child: ProjectTile(
          project: _project(),
          expanded: false,
          chatCount: 2,
          onToggle: () {},
          onNewChat: () {},
          onRemoveProject: () {},
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final size = tester.getSize(find.byType(AnimatedContainer));
    final decoration = container.decoration! as BoxDecoration;

    expect(size.height, lessThanOrEqualTo(32));
    expect(
      decoration.borderRadius,
      BorderRadius.circular(AleraTokens.radiusLg),
    );

    final inkWell = tester.widget<InkWell>(find.byType(InkWell).first);
    expect(inkWell.borderRadius, BorderRadius.circular(AleraTokens.radiusLg));
  });

  testWidgets('project options menu uses rounded dropdown entry', (
    tester,
  ) async {
    var removes = 0;

    await tester.pumpWidget(
      _Host(
        child: ProjectTile(
          project: _project(),
          expanded: false,
          chatCount: 2,
          onToggle: () {},
          onNewChat: () {},
          onRemoveProject: () => removes++,
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byType(ProjectTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('Remove project'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.borderRadius == BorderRadius.circular(AleraTokens.radiusLg),
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('Remove project'));
    await tester.pumpAndSettle();

    expect(removes, 1);
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
      home: Scaffold(
        body: Center(child: SizedBox(width: 280, child: child)),
      ),
    );
  }
}
