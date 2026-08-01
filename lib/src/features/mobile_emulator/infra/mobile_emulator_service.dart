import 'dart:async';

import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class MobileEmulatorService {
  MobileEmulatorService(this._client) {
    _connectionSubscription = _client.runtimeEvents
        .where((event) => event.name == aleraRuntimeHostConnectedEvent)
        .listen((_) => _supportCheck = null);
  }

  static const Duration _startupTimeout = Duration(minutes: 7);
  static const Duration _discoveryTimeout = Duration(seconds: 45);
  static const Duration _releaseTimeout = Duration(seconds: 45);

  final RuntimeHostClient _client;
  late final StreamSubscription<RuntimeHostEvent> _connectionSubscription;
  Future<void>? _supportCheck;

  Stream<RuntimeHostEvent> get changes => _client.runtimeEvents.where(
    (event) =>
        event.name == 'mobileEmulatorChanged' ||
        event.name == 'emulatorChanged' ||
        event.name == aleraRuntimeHostConnectedEvent,
  );

  void dispose() {
    unawaited(_connectionSubscription.cancel());
  }

  Future<Map<MobileEmulatorPlatform, MobileEmulatorCapability>>
  capabilities() async {
    final value = await _request('emulator.capabilities');
    final platforms = value['platforms'];
    return <MobileEmulatorPlatform, MobileEmulatorCapability>{
      for (final platform in MobileEmulatorPlatform.values)
        platform: MobileEmulatorCapability.fromJson(
          platforms is Map ? platforms[platform.key] : null,
        ),
    };
  }

  Future<List<MobileEmulatorDevice>> devices({
    MobileEmulatorPlatform? platform,
  }) async {
    final value = await _request('emulator.devices', <String, Object?>{
      if (platform != null) 'platform': platform.key,
    });
    final rawDevices = value['items'] ?? value['devices'];
    if (rawDevices is! List) {
      return const <MobileEmulatorDevice>[];
    }
    return <MobileEmulatorDevice>[
      for (final raw in rawDevices)
        if (MobileEmulatorDevice.fromJson(raw)
            case final MobileEmulatorDevice device)
          device,
    ];
  }

  Future<MobileEmulatorAttachment> attach({
    required String workspaceId,
    required MobileEmulatorPlatform platform,
    required String deviceId,
  }) async {
    final value = await _request('emulator.attach', <String, Object?>{
      'workspaceId': workspaceId,
      'platform': platform.key,
      'deviceId': deviceId,
    });
    final tab = value['tab'];
    final session = MobileEmulatorSession.fromJson(value['session']);
    if (tab is! Map || session == null) {
      throw const MobileEmulatorException(
        code: 'invalid_response',
        message: 'The runtime host returned an invalid emulator attachment.',
      );
    }
    return MobileEmulatorAttachment(
      tab: WorkspaceTabRecord.fromJson(
        Map<String, Object?>.from(tab.cast<String, Object?>()),
      ),
      session: session,
    );
  }

  Future<MobileEmulatorSession> acquire(MobileEmulatorTarget target) async {
    final value = await _request('emulator.acquire', target.toTabRequest());
    return _requiredSession(value);
  }

  Future<MobileEmulatorSession> release(MobileEmulatorTarget target) async {
    final value = await _request('emulator.release', target.toTabRequest());
    return _requiredSession(value);
  }

  Future<void> pointer({
    required MobileEmulatorTarget target,
    required String type,
    required double x,
    required double y,
  }) async {
    await _request('emulator.pointer', <String, Object?>{
      ...target.toTabRequest(),
      'interactive': true,
      'type': type,
      'x': x.clamp(0, 1),
      'y': y.clamp(0, 1),
    });
  }

  Future<void> typeText({
    required MobileEmulatorTarget target,
    required String text,
  }) async {
    if (text.isEmpty) {
      return;
    }
    await _request('emulator.type', <String, Object?>{
      ...target.toTabRequest(),
      'interactive': true,
      'text': text,
    });
  }

  Future<void> key({
    required MobileEmulatorTarget target,
    required String key,
  }) async {
    await _request('emulator.key', <String, Object?>{
      ...target.toTabRequest(),
      'interactive': true,
      'key': key,
    });
  }

  Future<Map<String, Object?>> _request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    await _ensureSupported();
    final response = await _client.runtimeRequest(type, payload, switch (type) {
      'emulator.attach' || 'emulator.acquire' => _startupTimeout,
      'emulator.capabilities' || 'emulator.devices' => _discoveryTimeout,
      'emulator.release' || 'emulator.detach' => _releaseTimeout,
      _ => null,
    });
    if (response is! Map) {
      throw const MobileEmulatorException(
        code: 'invalid_response',
        message: 'The runtime host returned an invalid emulator response.',
      );
    }
    final value = Map<String, Object?>.from(response.cast<String, Object?>());
    if (value['ok'] == false) {
      throw _failureFrom(value['error']);
    }
    return value;
  }

  Future<void> _ensureSupported() async {
    final pending = _supportCheck ??= _readSupport();
    try {
      await pending;
    } catch (_) {
      _supportCheck = null;
      rethrow;
    }
  }

  Future<void> _readSupport() async {
    final response = await _client.runtimeRequest('status.get');
    if (response is Map) {
      final capabilities = response['runtimeCapabilities'];
      if (capabilities is List &&
          capabilities.contains(aleraRuntimeHostMobileEmulatorCapability)) {
        return;
      }
    }
    throw const MobileEmulatorException(
      code: 'runtime_update_required',
      message: 'Runtime update required for mobile emulator support.',
    );
  }

  MobileEmulatorSession _requiredSession(Map<String, Object?> value) {
    final session = MobileEmulatorSession.fromJson(value['session']);
    if (session == null) {
      throw const MobileEmulatorException(
        code: 'invalid_response',
        message: 'The runtime host returned an invalid emulator session.',
      );
    }
    return session;
  }

  MobileEmulatorException _failureFrom(Object? raw) {
    if (raw is! Map) {
      return const MobileEmulatorException(
        code: 'emulator_error',
        message: 'The mobile emulator operation failed.',
      );
    }
    final steps = raw['nextSteps'];
    return MobileEmulatorException(
      code: raw['code'] is String ? raw['code'] as String : 'emulator_error',
      message: raw['message'] is String
          ? raw['message'] as String
          : 'The mobile emulator operation failed.',
      nextSteps: steps is List
          ? steps.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }
}
