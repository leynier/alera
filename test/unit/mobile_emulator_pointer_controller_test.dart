import 'dart:ui';

import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_pointer_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'secondary down stays inert while a primary gesture keeps moving and ends',
    (tester) async {
      const target = MobileEmulatorTarget(
        tabId: 'tab-1',
        workspaceId: 'workspace-1',
      );
      final events =
          <({String type, Offset position, MobileEmulatorTarget target})>[];
      var focusRequests = 0;
      final controller = MobileEmulatorPointerController(
        onPointer: (type, position, eventTarget) {
          events.add((type: type, position: position, target: eventTarget));
        },
      );
      addTearDown(controller.finish);

      controller.down(
        const PointerDownEvent(
          pointer: 1,
          position: Offset(20, 40),
          buttons: kSecondaryMouseButton,
        ),
        const Size(200, 400),
        target: target,
        requestFocus: () => focusRequests += 1,
      );
      controller.end(
        const PointerUpEvent(pointer: 1, position: Offset(30, 60)),
        const Size(200, 400),
      );

      expect(focusRequests, 0);
      expect(events, isEmpty);

      controller.down(
        const PointerDownEvent(
          pointer: 2,
          position: Offset(50, 100),
          buttons: kPrimaryButton | kSecondaryMouseButton,
        ),
        const Size(200, 400),
        target: target,
        requestFocus: () => focusRequests += 1,
      );
      controller.down(
        const PointerDownEvent(
          pointer: 3,
          position: Offset(10, 20),
          buttons: kSecondaryMouseButton,
        ),
        const Size(200, 400),
        target: target,
        requestFocus: () => focusRequests += 1,
      );
      controller.move(
        const PointerMoveEvent(
          pointer: 2,
          position: Offset(100, 200),
          buttons: kSecondaryMouseButton,
        ),
        const Size(200, 400),
      );
      await tester.pump(const Duration(milliseconds: 33));
      controller.end(
        const PointerUpEvent(pointer: 2, position: Offset(180, 360)),
        const Size(200, 400),
      );

      expect(focusRequests, 1);
      expect(
        events.map((event) => (event.type, event.position)),
        <(String, Offset)>[
          ('begin', const Offset(0.25, 0.25)),
          ('move', const Offset(0.5, 0.5)),
          ('end', const Offset(0.9, 0.9)),
        ],
      );
      expect(events.every((event) => identical(event.target, target)), isTrue);
    },
  );
}
