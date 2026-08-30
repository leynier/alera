import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_connection_health.g.dart';

class const HostConnectionHealth({
  final String phase = 'connecting',
  final String? transport,
  final String? error,
  final DateTime? nextRetryAt,
  final DateTime? connectedAt,
});

@riverpod
class HostConnectionHealthController extends _$HostConnectionHealthController {
  @override
  HostConnectionHealth build(String hostId) => const HostConnectionHealth();
  void update(HostConnectionHealth health) => state = health;
}
