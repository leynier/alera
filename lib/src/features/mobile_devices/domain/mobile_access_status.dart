import 'package:alera/src/features/mobile_devices/domain/mobile_device.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_offer.dart';

class MobileGatewaySettings {
  const MobileGatewaySettings({
    required this.enabled,
    required this.bindHost,
    required this.port,
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
      serverPublicKeyB64: publicKey is String && publicKey.trim().isNotEmpty
          ? publicKey
          : null,
    );
  }

  final bool enabled;
  final String bindHost;
  final int port;
  final String? serverPublicKeyB64;
}

class MobileAccessStatus {
  const MobileAccessStatus({
    required this.protocolVersion,
    required this.settings,
    required this.devices,
    required this.activePairings,
    this.runtimeHostActive,
  });

  factory MobileAccessStatus.fromJson(Map<String, Object?> json) {
    final settings = json['settings'];
    if (settings is! Map) {
      throw const FormatException('Mobile status payload is malformed.');
    }
    final version = json['protocolVersion'];
    final runtimeHostActive = json['runtimeHostActive'];
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
    );
  }

  final int protocolVersion;
  final MobileGatewaySettings settings;
  final List<MobileDevice> devices;
  final List<MobilePairingOffer> activePairings;
  final bool? runtimeHostActive;
}
