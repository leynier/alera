import 'package:alera_browser/src/native_browser_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports the first layout bounds', (tester) async {
    final boundsLog = <Rect>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Directionality(
          textDirection: .ltr,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: AleraNativeBrowserSurface(
                onBoundsChanged: (bounds, scale) async {
                  expect(scale, 1);
                  boundsLog.add(bounds);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(boundsLog, hasLength(1));
    expect(boundsLog.single.size, const Size(320, 240));
  });

  testWidgets('reports layout-only size changes', (tester) async {
    final boundsLog = <Size>[];
    final size = ValueNotifier<Size>(const Size(320, 240));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Directionality(
          textDirection: .ltr,
          child: Center(
            child: ValueListenableBuilder<Size>(
              valueListenable: size,
              builder: (context, value, _) {
                return SizedBox(
                  width: value.width,
                  height: value.height,
                  child: AleraNativeBrowserSurface(
                    onBoundsChanged: (bounds, scale) async {
                      boundsLog.add(bounds.size);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(boundsLog, contains(const Size(320, 240)));

    size.value = const Size(480, 360);
    await tester.pump();
    await tester.pump();

    expect(boundsLog.last, const Size(480, 360));
  });

  testWidgets('dedupes identical bounds', (tester) async {
    var callbacks = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Directionality(
          textDirection: .ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: AleraNativeBrowserSurface(
                onBoundsChanged: (bounds, scale) async {
                  callbacks++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(callbacks, 1);

    await tester.pump();
    await tester.pump();
    expect(callbacks, 1);
  });
}
