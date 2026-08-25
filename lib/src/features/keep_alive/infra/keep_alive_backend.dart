import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:alera/src/rust/api/keep_alive.dart';

abstract interface class KeepAliveBackend {
  Future<KeepAliveSnapshot> setEnabled(bool enabled);
  Future<KeepAliveSnapshot> status();
}

class RustKeepAliveBackend implements KeepAliveBackend {
  const RustKeepAliveBackend();

  @override
  Future<KeepAliveSnapshot> setEnabled(bool enabled) async {
    return _fromDto(await setKeepAlive(enabled: enabled));
  }

  @override
  Future<KeepAliveSnapshot> status() async {
    return _fromDto(await keepAliveStatus());
  }
}

KeepAliveSnapshot _fromDto(KeepAliveStatusDto dto) {
  return KeepAliveSnapshot(
    active: dto.active,
    system: dto.system,
    display: dto.display,
    error: dto.error,
  );
}
