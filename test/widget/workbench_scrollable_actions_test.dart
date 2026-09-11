import 'package:alera/src/features/workbench/presentation/workbench_scrollable_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leaves leftover row width to the expanded sibling', (
    tester,
  ) async {
    const label = 'lib/src/features/projects/application/projects_service.dart';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 40,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 8),
                  ),
                ),
                WorkbenchScrollableActions(
                  children: <Widget>[SizedBox(width: 80, child: Text('M'))],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final row = tester.getRect(find.byType(Row).first);
    expect(tester.getSize(find.text(label)).width, closeTo(560, 0.5));
    expect(
      tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines,
      isFalse,
    );
    expect(tester.getRect(find.text('M')).right, closeTo(row.right, 0.5));
  });

  testWidgets(
    'scrolls trailing actions when they exceed the incoming max width',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 40,
              child: WorkbenchScrollableActions(
                children: <Widget>[
                  SizedBox(width: 60, child: Text('A')),
                  SizedBox(width: 60, child: Text('B')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(WorkbenchScrollableActions)).width, 80);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    },
  );
}
