import 'package:alera/src/features/mobile_devices/domain/mobile_device.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_offer.dart';

enum MobileEndpointMode {
  loopback,
  tailscale,
  manual;

  /// Defaults to loopback for unknown values so the desktop keeps working
  /// against runtimes that predate the endpoint mode field.
  static MobileEndpointMode fromWire(Object? value) {
    return switch (value) {
      'tailscale' => MobileEndpointMode.tailscale,
      'manual' => MobileEndpointMode.manual,
      _ => MobileEndpointMode.loopback,
    };
  }

  String get wireName => name;
}

class MobileGatewaySettings {
  const MobileGatewaySettings({
    required this.enabled,
    required this.bindHost,
    required this.port,
    this.endpointMode = MobileEndpointMode.loopback,
    this.serverPublicKeyB64,
  });

  factory MobileGatewaySettings.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    final bindHost = json['bindHost'];
    final port = json['port'];
    if (enabled is! bool || bindHost is! String || port is! num) {
      throw const FormatException(
        'Mobile gateway settings payload is malformed.',
      );
    }
    final publicKey = json['serverPublicKeyB64'];
    return MobileGatewaySettings(
      enabled: enabled,
      bindHost: bindHost,
      port: port.toInt(),
      endpointMode: MobileEndpointMode.fromWire(json['endpointMode']),
      serverPublicKeyB64: publicKey is String && publicKey.trim().isNotEmpty
          ? publicKey
          : null,
    );
  }

  final bool enabled;
  final String bindHost;
  final int port;
  final MobileEndpointMode endpointMode;
  final String? serverPublicKeyB64;
}

class MobileTailscaleStatus {
  const MobileTailscaleStatus({
    required this.detected,
    required this.running,
    this.tailnetIp,
    this.error,
  });

  factory MobileTailscaleStatus.fromJson(Map<String, Object?> json) {
    final tailnetIp = json['tailnetIp'];
    final error = json['error'];
    return MobileTailscaleStatus(
      detected: json['detected'] == true,
      running: json['running'] == true,
      tailnetIp: tailnetIp is String && tailnetIp.trim().isNotEmpty
          ? tailnetIp
          : null,
      error: error is String && error.trim().isNotEmpty ? error : null,
    );
  }

  final bool detected;
  final bool running;
  final String? tailnetIp;
  final String? error;
}

class MobileAccessStatus {
  const MobileAccessStatus({
    required this.protocolVersion,
    required this.settings,
    required this.devices,
    required this.activePairings,
    this.runtimeHostActive,
    this.tailscale,
  });

  factory MobileAccessStatus.fromJson(Map<String, Object?> json) {
    final settings = json['settings'];
    if (settings is! Map) {
      throw const FormatException('Mobile status payload is malformed.');
    }
    final version = json['protocolVersion'];
    final runtimeHostActive = json['runtimeHostActive'];
    final tailscale = json['tailscale'];
    return MobileAccessStatus(
      protocolVersion: version is num ? version.toInt() : 0,
      settings: MobileGatewaySettings.fromJson(
        Map<String, Object?>.from(settings),
      ),
      devices: <MobileDevice>[
        for (final device in (json['devices'] as List? ?? const <Object?>[]))
          if (device is Map)
            MobileDevice.fromJson(Map<String, Object?>.from(device)),
      ],
      activePairings: <MobilePairingOffer>[
        for (final offer
            in (json['activePairings'] as List? ?? const <Object?>[]))
          if (offer is Map)
            MobilePairingOffer.fromJson(Map<String, Object?>.from(offer)),
      ],
      runtimeHostActive: runtimeHostActive is bool ? runtimeHostActive : null,
      tailscale: tailscale is Map
          ? MobileTailscaleStatus.fromJson(Map<String, Object?>.from(tailscale))
          : null,
    );
  }

  final int protocolVersion;
  final MobileGatewaySettings settings;
  final List<MobileDevice> devices;
  final List<MobilePairingOffer> activePairings;
  final bool? runtimeHostActive;
  final MobileTailscaleStatus? tailscale;
}
