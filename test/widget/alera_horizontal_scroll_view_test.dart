import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('horizontalMouseWheelDelta keeps Shift and trackpad on Flutter', (
    tester,
  ) async {
    const mouseVertical = PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      scrollDelta: Offset(0, 20),
    );
    expect(horizontalMouseWheelDelta(mouseVertical), 20);
    expect(
      horizontalMouseWheelDelta(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          scrollDelta: Offset(15, 20),
        ),
      ),
      isNull,
    );
    expect(
      horizontalMouseWheelDelta(
        const PointerScrollEvent(
          kind: PointerDeviceKind.trackpad,
          scrollDelta: Offset(0, 20),
        ),
      ),
      isNull,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(horizontalMouseWheelDelta(mouseVertical), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('maps a vertical mouse wheel onto a horizontal strip', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller: controller));
    expect(controller.offset, 0);

    await _scrollMouse(tester, const Offset(0, 40));
    expect(controller.offset, 40);
  });

  testWidgets('keeps native horizontal wheel delta', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller: controller));

    await _scrollMouse(tester, const Offset(25, 0));
    expect(controller.offset, 25);
  });

  testWidgets('does not double-apply Shift+wheel', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller: controller));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _scrollMouse(tester, const Offset(0, 20));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.offset, 20);
  });

  testWidgets('does not remap a vertical trackpad gesture', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller: controller));

    await _scroll(
      tester,
      const Offset(0, 40),
      kind: PointerDeviceKind.trackpad,
    );
    expect(controller.offset, 0);
  });

  testWidgets('does not claim the wheel when the strip has no overflow', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller: controller, viewportWidth: 400, childWidth: 80),
    );

    await _scrollMouse(tester, const Offset(0, 40));
    expect(controller.offset, 0);
  });

  testWidgets('reverses wheel delta for reverse strips', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller: controller, reverse: true));
    expect(controller.offset, 0);

    await _scrollMouse(tester, const Offset(0, -40));
    expect(controller.offset, 40);
  });

  testWidgets('maps a vertical mouse wheel onto a horizontal ListView', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 40,
              child: AleraMouseWheelHorizontalScroll(
                controller: controller,
                child: ListView(
                  controller: controller,
                  scrollDirection: .horizontal,
                  children: const <Widget>[
                    SizedBox(width: 200, child: Text('wide')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _scrollMouse(tester, const Offset(0, 30));
    expect(controller.offset, 30);
  });

  testWidgets('overflowing strip claims the wheel from a vertical parent', (
    tester,
  ) async {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 200,
            child: ListView(
              controller: vertical,
              children: <Widget>[
                SizedBox(
                  height: 40,
                  child: AleraHorizontalScrollView(
                    controller: horizontal,
                    child: const SizedBox(width: 400, child: Text('wide')),
                  ),
                ),
                const SizedBox(height: 800, child: Text('below')),
              ],
            ),
          ),
        ),
      ),
    );

    await _scrollMouse(
      tester,
      const Offset(0, 40),
      of: find.byType(AleraHorizontalScrollView),
    );
    expect(horizontal.offset, 40);
    expect(vertical.offset, 0);
  });

  testWidgets('wheel at the horizontal edge continues the vertical parent', (
    tester,
  ) async {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 200,
            child: ListView(
              controller: vertical,
              children: <Widget>[
                SizedBox(
                  height: 40,
                  child: AleraHorizontalScrollView(
                    controller: horizontal,
                    child: const SizedBox(width: 160, child: Text('wide')),
                  ),
                ),
                const SizedBox(height: 800, child: Text('below')),
              ],
            ),
          ),
        ),
      ),
    );

    await _scrollMouse(
      tester,
      const Offset(0, 1000),
      of: find.byType(AleraHorizontalScrollView),
    );
    expect(horizontal.offset, horizontal.position.maxScrollExtent);
    expect(vertical.offset, 0);

    await _scrollMouse(
      tester,
      const Offset(0, 40),
      of: find.byType(AleraHorizontalScrollView),
    );
    expect(horizontal.offset, horizontal.position.maxScrollExtent);
    expect(vertical.offset, 40);
  });
}

Widget _harness({
  required ScrollController controller,
  bool reverse = false,
  double viewportWidth = 120,
  double childWidth = 400,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: viewportWidth,
          height: 40,
          child: AleraHorizontalScrollView(
            controller: controller,
            reverse: reverse,
            child: SizedBox(width: childWidth, child: const Text('wide')),
          ),
        ),
      ),
    ),
  );
}

Future<void> _scrollMouse(
  WidgetTester tester,
  Offset scrollDelta, {
  Finder? of,
}) {
  return _scroll(tester, scrollDelta, kind: PointerDeviceKind.mouse, of: of);
}

Future<void> _scroll(
  WidgetTester tester,
  Offset scrollDelta, {
  required PointerDeviceKind kind,
  Finder? of,
}) async {
  final location = tester.getCenter(of ?? find.byType(Scrollable));
  final pointer = TestPointer(1, kind);
  pointer.hover(location);
  await tester.sendEventToBinding(pointer.scroll(scrollDelta));
  await tester.pump();
}
