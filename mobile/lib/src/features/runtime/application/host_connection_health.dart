import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_connection_health.g.dart';

class HostConnectionHealth {
  const HostConnectionHealth({
    this.phase = 'connecting',
    this.transport,
    this.error,
    this.nextRetryAt,
    this.connectedAt,
  });
  final String phase;
  final String? transport;
  final String? error;
  final DateTime? nextRetryAt;
  final DateTime? connectedAt;
}

@riverpod
class HostConnectionHealthController extends _$HostConnectionHealthController {
  @override
  HostConnectionHealth build(String hostId) => const HostConnectionHealth();
  void update(HostConnectionHealth health) => state = health;
}
