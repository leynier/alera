import 'dart:async';

import 'package:alera/src/features/keep_alive/application/keep_alive_service.dart';
import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:alera/src/features/keep_alive/infra/keep_alive_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeepAliveService', () {
    test('enables and disables through the backend', () async {
      final backend = _FakeKeepAliveBackend();
      final service = KeepAliveService(backend: backend);

      final enabled = await service.setEnabled(true);
      expect(enabled.active, isTrue);
      expect(enabled.system, isTrue);
      expect(enabled.display, isTrue);
      expect(backend.enabled, isTrue);

      final disabled = await service.setEnabled(false);
      expect(disabled.active, isFalse);
      expect(backend.enabled, isFalse);
    });

    test('surfaces backend errors without throwing', () async {
      final backend = _FakeKeepAliveBackend()..failWith = 'not supported';
      final service = KeepAliveService(backend: backend);

      final failed = await service.setEnabled(true);

      expect(failed.active, isFalse);
      expect(failed.error, contains('not supported'));
      expect(backend.enabled, isFalse);
    });

    test('serializes enable then disable while start is pending', () async {
      final backend = _FakeKeepAliveBackend()..startGate = Completer<void>();
      final service = KeepAliveService(backend: backend);

      final enable = service.setEnabled(true);
      final disable = service.setEnabled(false);
      backend.startGate!.complete();
      await Future.wait<KeepAliveSnapshot>(<Future<KeepAliveSnapshot>>[
        enable,
        disable,
      ]);

      expect(backend.enabled, isFalse);
      expect(service.snapshot.active, isFalse);
    });
  });
}

class _FakeKeepAliveBackend implements KeepAliveBackend {
  bool enabled = false;
  String? failWith;
  Completer<void>? startGate;

  @override
  Future<KeepAliveSnapshot> setEnabled(bool enabled) async {
    await startGate?.future;
    if (enabled && failWith != null) {
      throw StateError(failWith!);
    }
    this.enabled = enabled;
    if (enabled) {
      return const KeepAliveSnapshot.active();
    }
    return const KeepAliveSnapshot.inactive();
  }

  @override
  Future<KeepAliveSnapshot> status() async {
    if (enabled) {
      return const KeepAliveSnapshot.active();
    }
    return const KeepAliveSnapshot.inactive();
  }
}
