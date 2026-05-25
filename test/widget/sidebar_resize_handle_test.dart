import 'package:alera/src/features/projects/presentation/widgets/sidebar_resize_handle.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sidebar resize handle reacts to hover and drag updates', (
    tester,
  ) async {
    final resizedWidths = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SidebarResizeHandle(
              currentWidth: 240,
              onResize: resizedWidths.add,
            ),
          ),
        ),
      ),
    );

    final animated = find.byType(AnimatedContainer);
    expect(tester.getSize(animated).width, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(SidebarResizeHandle)));
    await tester.pumpAndSettle();
    expect(tester.getSize(animated).width, 2);

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(SidebarResizeHandle)),
    );
    await drag.moveBy(const Offset(24, 0));
    await drag.up();
    await tester.pumpAndSettle();

    expect(resizedWidths, <double>[264]);

    final cancelledDrag = await tester.startGesture(
      tester.getCenter(find.byType(SidebarResizeHandle)),
    );
    await tester.pump();
    await cancelledDrag.cancel();
    await tester.pumpAndSettle();

    await mouse.moveTo(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(tester.getSize(animated).width, 1);
  });
}
