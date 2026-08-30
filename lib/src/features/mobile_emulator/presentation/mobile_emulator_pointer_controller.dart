import 'dart:async';
import 'dart:ui';

import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:flutter/gestures.dart';

typedef MobileEmulatorPointerDispatch = void Function(
  String type,
  Offset position,
  MobileEmulatorTarget target,
);

class MobileEmulatorPointerController({
  required final MobileEmulatorPointerDispatch onPointer,
}) {
  Timer? _moveTimer;
  Offset? _pendingMove;
  Offset? _lastPosition;
  int? _activePointerId;
  MobileEmulatorTarget? _activeTarget;

  void down(
    PointerDownEvent event,
    Size size, {
    required MobileEmulatorTarget target,
    required void Function() requestFocus,
  }) {
    if (!_hasUsableSize(size) ||
        _activePointerId != null ||
        event.buttons & kPrimaryButton == 0) {
      return;
    }
    requestFocus();
    _activePointerId = event.pointer;
    _activeTarget = target;
    final position = _normalize(event, size);
    _lastPosition = position;
    onPointer('begin', position, target);
  }

  void move(PointerMoveEvent event, Size size) {
    if (!_hasUsableSize(size) || _activePointerId != event.pointer) {
      return;
    }
    final position = _normalize(event, size);
    _lastPosition = position;
    _pendingMove = position;
    _moveTimer ??= Timer(const Duration(milliseconds: 33), () {
      _moveTimer = null;
      final pending = _pendingMove;
      _pendingMove = null;
      final target = _activeTarget;
      if (pending != null && target != null) {
        onPointer('move', pending, target);
      }
    });
  }

  void end(PointerEvent event, Size size) {
    if (!_hasUsableSize(size) || _activePointerId != event.pointer) {
      return;
    }
    finish(position: _normalize(event, size));
  }

  void finish({Offset? position}) {
    final target = _activeTarget;
    final endpoint = position ?? _lastPosition;
    _moveTimer?.cancel();
    _moveTimer = null;
    _pendingMove = null;
    _lastPosition = null;
    _activePointerId = null;
    _activeTarget = null;
    if (target != null && endpoint != null) {
      onPointer('end', endpoint, target);
    }
  }

  static bool _hasUsableSize(Size size) => size.width > 0 && size.height > 0;

  static Offset _normalize(PointerEvent event, Size size) => Offset(
    (event.localPosition.dx / size.width).clamp(0, 1).toDouble(),
    (event.localPosition.dy / size.height).clamp(0, 1).toDouble(),
  );
}
