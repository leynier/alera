import 'dart:async';

import 'package:alera/src/features/keep_alive/application/keep_alive_service.dart';
import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:alera/src/features/keep_alive/infra/keep_alive_backend.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'keep_alive_providers.g.dart';

final _keepAliveLog = Logger('KeepAlive');

@Riverpod(keepAlive: true)
KeepAliveBackend keepAliveBackend(Ref ref) {
  return const RustKeepAliveBackend();
}

@Riverpod(keepAlive: true)
KeepAliveService keepAliveService(Ref ref) {
  final service = KeepAliveService(
    backend: ref.watch(keepAliveBackendProvider),
  );
  ref.onDispose(() {
    unawaited(service.dispose().catchError(_logKeepAliveError));
  });
  return service;
}

@Riverpod(keepAlive: true)
class KeepAliveController extends _$KeepAliveController {
  var _generation = 0;

  @override
  KeepAliveSnapshot build() {
    _generation = 0;
    final service = ref.watch(keepAliveServiceProvider);
    final enabled = ref
        .read(settingsControllerProvider)
        .general
        .keepAliveEnabled;
    unawaited(_publish(service.setEnabled(enabled)));
    ref.listen<bool>(
      settingsControllerProvider.select(
        (settings) => settings.general.keepAliveEnabled,
      ),
      (_, next) {
        unawaited(_publish(service.setEnabled(next)));
      },
    );
    return service.snapshot;
  }

  Future<void> toggle() async {
    final generation = ++_generation;
    final desired = !ref
        .read(settingsControllerProvider)
        .general
        .keepAliveEnabled;
    final service = ref.read(keepAliveServiceProvider);
    final next = await service.setEnabled(desired);
    if (!ref.mounted || generation != _generation) {
      return;
    }
    state = next;
    if (desired && !next.active) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setKeepAliveEnabled(desired);
  }

  Future<void> _publish(Future<KeepAliveSnapshot> operation) async {
    final generation = ++_generation;
    try {
      final next = await operation;
      if (ref.mounted && generation == _generation) {
        state = next;
      }
    } catch (error, stackTrace) {
      _logKeepAliveError(error, stackTrace);
    }
  }
}

@Riverpod(keepAlive: true)
void keepAliveCoordinator(Ref ref) {
  ref.watch(keepAliveControllerProvider);
}

void _logKeepAliveError(Object error, StackTrace stackTrace) {
  _keepAliveLog.warning('keep-alive work failed', error, stackTrace);
}
