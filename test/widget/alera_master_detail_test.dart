import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('master detail splitter moves within its width limits', (
    tester,
  ) async {
    const masterKey = ValueKey<String>('master-detail-master');
    const handleKey = ValueKey<String>('alera-master-detail-resize-handle');

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 320,
          child: AleraMasterDetail(
            masterTitle: 'Projects',
            master: SizedBox(key: masterKey),
            detail: const SizedBox(),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(masterKey)).width, 240);

    final handle = find.byKey(handleKey);
    final dragRight = await tester.startGesture(tester.getCenter(handle));
    await dragRight.moveBy(const Offset(64, 0));
    await dragRight.up();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(masterKey)).width, 304);

    final dragPastMinimum = await tester.startGesture(tester.getCenter(handle));
    await dragPastMinimum.moveBy(const Offset(-200, 0));
    await dragPastMinimum.up();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(masterKey)).width, 180);

    final dragPastMaximum = await tester.startGesture(tester.getCenter(handle));
    await dragPastMaximum.moveBy(const Offset(500, 0));
    await dragPastMaximum.up();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(masterKey)).width, 420);
  });
}
