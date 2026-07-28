import 'dart:async';

import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';

class MobileEmulatorLeaseCoordinator {
  MobileEmulatorLeaseCoordinator(this._service);

  static const Duration releaseGrace = Duration(milliseconds: 1500);

  final MobileEmulatorService _service;
  final Map<String, _MobileEmulatorLease> _leases =
      <String, _MobileEmulatorLease>{};

  Future<MobileEmulatorSession> acquire(MobileEmulatorTarget target) async {
    final lease = _leases.putIfAbsent(
      target.tabId,
      () => _MobileEmulatorLease(target),
    );
    lease.releaseTimer?.cancel();
    lease.releaseTimer = null;
    lease.references += 1;
    final pendingRelease = lease.pendingRelease;
    if (pendingRelease != null) {
      await pendingRelease;
    }
    if (!identical(_leases[target.tabId], lease)) {
      return acquire(target);
    }
    final session = lease.session;
    if (!lease.parked && session != null) {
      return session;
    }
    final pending = lease.pendingAcquire ??= _service.acquire(target);
    try {
      final session = await pending;
      lease.session = session;
      lease.parked = false;
      return session;
    } catch (_) {
      if (lease.references > 0) {
        lease.references -= 1;
      }
      if (lease.references == 0) {
        _leases.remove(target.tabId);
      }
      rethrow;
    } finally {
      lease.pendingAcquire = null;
    }
  }

  void release(String tabId) {
    final lease = _leases[tabId];
    if (lease == null) {
      return;
    }
    if (lease.references > 0) {
      lease.references -= 1;
    }
    if (lease.references != 0) {
      return;
    }
    lease.releaseTimer?.cancel();
    lease.releaseTimer = Timer(releaseGrace, () async {
      if (lease.references != 0) {
        return;
      }
      await _releaseLease(tabId, lease);
    });
  }

  Future<void> suspend(String tabId) async {
    final lease = _leases[tabId];
    if (lease == null) {
      return;
    }
    if (lease.references > 0) {
      lease.references -= 1;
    }
    if (lease.references != 0) {
      return;
    }
    lease.releaseTimer?.cancel();
    await _releaseLease(tabId, lease);
  }

  Future<MobileEmulatorSession> refresh(MobileEmulatorTarget target) async {
    final session = await _service.acquire(target);
    final lease = _leases[target.tabId];
    lease?.session = session;
    lease?.parked = false;
    return session;
  }

  Future<void> _releaseLease(String tabId, _MobileEmulatorLease lease) {
    if (lease.pendingRelease case final pending?) {
      return pending;
    }
    lease.parked = true;
    late final Future<void> pending;
    pending = _service
        .release(lease.target)
        .then<void>((session) {
          lease.session = session;
        })
        .catchError((_) {
          // A later acquire always refreshes after an uncertain release.
        })
        .whenComplete(() {
          if (identical(lease.pendingRelease, pending)) {
            lease.pendingRelease = null;
          }
          if (lease.references == 0 && identical(_leases[tabId], lease)) {
            _leases.remove(tabId);
          }
        });
    lease.pendingRelease = pending;
    return pending;
  }

  void invalidate(String tabId) {
    _leases.remove(tabId)?.releaseTimer?.cancel();
  }

  void close(String tabId) => invalidate(tabId);

  void dispose() {
    for (final lease in _leases.values) {
      lease.releaseTimer?.cancel();
    }
    _leases.clear();
  }
}

class _MobileEmulatorLease {
  _MobileEmulatorLease(this.target);

  final MobileEmulatorTarget target;
  int references = 0;
  Timer? releaseTimer;
  MobileEmulatorSession? session;
  Future<MobileEmulatorSession>? pendingAcquire;
  Future<void>? pendingRelease;
  bool parked = false;
}
