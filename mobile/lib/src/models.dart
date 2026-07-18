import 'dart:convert';
import 'dart:io';

const int aleraMobileProtocolVersion = 1;

class PairingOffer {
  const PairingOffer({
    required this.version,
    required this.pairingId,
    required this.endpoint,
    required this.runtimeId,
    required this.hostName,
    required this.pairingSecret,
    required this.expiresAt,
    this.serverPublicKeyB64,
  });

  final int version;
  final String pairingId;
  final String endpoint;
  final String runtimeId;
  final String hostName;
  final String pairingSecret;
  final String? serverPublicKeyB64;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  static PairingOffer parse(String input) {
    final value = jsonDecode(input.trim());
    if (value is! Map<String, Object?>) {
      throw const FormatException('Pairing Offer Must Be A JSON Object');
    }
    return PairingOffer.fromJson(value);
  }

  factory PairingOffer.fromJson(Map<String, Object?> json) {
    final version = _intField(json, 'v');
    if (version != aleraMobileProtocolVersion) {
      throw FormatException('Unsupported Pairing Version $version');
    }
    final expiresAt = DateTime.parse(_stringField(json, 'expiresAt'));
    final endpoint = _stringField(json, 'endpoint');
    _validatePairingEndpoint(endpoint);
    final offer = PairingOffer(
      version: version,
      pairingId: _stringField(json, 'pairingId'),
      endpoint: endpoint,
      runtimeId: _stringField(json, 'runtimeId'),
      hostName: _stringField(json, 'hostName'),
      pairingSecret: _stringField(json, 'pairingSecret'),
      serverPublicKeyB64: _optionalStringField(json, 'serverPublicKeyB64'),
      expiresAt: expiresAt,
    );
    if (offer.isExpired) {
      throw const FormatException('Pairing Offer Expired');
    }
    return offer;
  }
}

void _validatePairingEndpoint(String endpoint) {
  final uri = Uri.tryParse(endpoint.trim());
  if (uri == null ||
      uri.scheme.isEmpty ||
      uri.host.isEmpty ||
      (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    throw const FormatException('Pairing Endpoint Must Use ws:// Or wss://');
  }
  if (!uri.hasPort || uri.port == 0) {
    throw const FormatException('Pairing Endpoint Must Include A Valid Port');
  }
  if (uri.scheme == 'ws' &&
      !_isLocalPairingHost(uri.host) &&
      !_isTailscalePairingHost(uri.host)) {
    throw const FormatException(
      'Plaintext Pairing Endpoint Must Use Localhost, Loopback, Or A '
      'Tailscale Tailnet Address',
    );
  }
}

bool _isLocalPairingHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost') {
    return true;
  }
  return InternetAddress.tryParse(host)?.isLoopback ?? false;
}

/// Tailscale tailnet ranges (IPv4 100.64.0.0/10, IPv6 fd7a:115c:a1e0::/48).
/// Traffic to these addresses rides the device's WireGuard tunnel, so
/// plaintext ws:// is acceptable. Mirrors the runtime's `is_tailscale_ip`.
bool _isTailscalePairingHost(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    return false;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127;
  }
  return bytes.length >= 6 &&
      bytes[0] == 0xfd &&
      bytes[1] == 0x7a &&
      bytes[2] == 0x11 &&
      bytes[3] == 0x5c &&
      bytes[4] == 0xa1 &&
      bytes[5] == 0xe0;
}

class PairedHostProfile {
  const PairedHostProfile({
    required this.id,
    required this.displayName,
    required this.endpoint,
    required this.runtimeId,
    required this.deviceId,
    required this.pairedAt,
    this.serverPublicKeyB64,
  });

  final String id;
  final String displayName;
  final String endpoint;
  final String runtimeId;
  final String deviceId;
  final String? serverPublicKeyB64;
  final DateTime pairedAt;

  factory PairedHostProfile.fromPairingResult(
    PairingOffer offer,
    PairedDeviceCredentials credentials,
  ) {
    // A pair response from a different runtime than the offer promised means
    // the endpoint reached the wrong host (for example a non-tailnet CGNAT
    // address); refuse to store credentials for it.
    if (credentials.runtimeId != offer.runtimeId) {
      throw const FormatException(
        'Pairing Response Runtime Id Does Not Match The Offer',
      );
    }
    return PairedHostProfile(
      id: offer.runtimeId,
      displayName: offer.hostName,
      endpoint: offer.endpoint,
      runtimeId: credentials.runtimeId,
      deviceId: credentials.deviceId,
      serverPublicKeyB64: offer.serverPublicKeyB64,
      pairedAt: DateTime.now().toUtc(),
    );
  }

  factory PairedHostProfile.fromJson(Map<String, Object?> json) {
    final endpoint = _stringField(json, 'endpoint');
    _validatePairingEndpoint(endpoint);
    return PairedHostProfile(
      id: _stringField(json, 'id'),
      displayName: _stringField(json, 'displayName'),
      endpoint: endpoint,
      runtimeId: _stringField(json, 'runtimeId'),
      deviceId: _stringField(json, 'deviceId'),
      serverPublicKeyB64: _optionalStringField(json, 'serverPublicKeyB64'),
      pairedAt: DateTime.parse(_stringField(json, 'pairedAt')),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'displayName': displayName,
      'endpoint': endpoint,
      'runtimeId': runtimeId,
      'deviceId': deviceId,
      'serverPublicKeyB64': serverPublicKeyB64,
      'pairedAt': pairedAt.toUtc().toIso8601String(),
    };
  }
}

class PairedDeviceCredentials {
  const PairedDeviceCredentials({
    required this.deviceId,
    required this.displayName,
    required this.runtimeId,
    required this.deviceToken,
  });

  final String deviceId;
  final String displayName;
  final String runtimeId;
  final String deviceToken;

  factory PairedDeviceCredentials.fromJson(Map<String, Object?> json) {
    return PairedDeviceCredentials(
      deviceId: _stringField(json, 'deviceId'),
      displayName: _stringField(json, 'displayName'),
      runtimeId: _stringField(json, 'runtimeId'),
      deviceToken: _stringField(json, 'deviceToken'),
    );
  }
}

class MobileRuntimeStatus {
  const MobileRuntimeStatus({
    required this.protocolVersion,
    required this.devices,
    required this.activePairings,
  });

  final int protocolVersion;
  final List<MobileDeviceSummary> devices;
  final List<Object?> activePairings;

  factory MobileRuntimeStatus.fromJson(Map<String, Object?> json) {
    return MobileRuntimeStatus(
      protocolVersion: _intField(json, 'protocolVersion'),
      devices: <MobileDeviceSummary>[
        for (final item in _listField(json, 'devices'))
          if (item is Map) MobileDeviceSummary.fromJson(_dynamicMap(item)),
      ],
      activePairings: _listField(json, 'activePairings'),
    );
  }
}

class MobileDeviceSummary {
  const MobileDeviceSummary({
    required this.id,
    required this.displayName,
    required this.permission,
    this.lastSeenAt,
    this.revokedAt,
  });

  final String id;
  final String displayName;
  final String permission;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  factory MobileDeviceSummary.fromJson(Map<String, Object?> json) {
    return MobileDeviceSummary(
      id: _stringField(json, 'id'),
      displayName: _stringField(json, 'displayName'),
      permission: _stringField(json, 'permission'),
      lastSeenAt: _optionalDateTimeField(json, 'lastSeenAt'),
      revokedAt: _optionalDateTimeField(json, 'revokedAt'),
    );
  }
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.repoPath,
  });

  final String id;
  final String name;
  final String repoPath;

  factory ProjectSummary.fromJson(Map<String, Object?> json) {
    return ProjectSummary(
      id: _stringField(json, 'id'),
      name: _stringField(json, 'name'),
      repoPath: _stringField(json, 'repoPath'),
    );
  }
}

class ProjectBranches {
  const ProjectBranches({
    required this.projectId,
    required this.branches,
    required this.localBranches,
  });

  final String projectId;
  final List<String> branches;
  final List<String> localBranches;

  factory ProjectBranches.fromJson(Map<String, Object?> json) {
    return ProjectBranches(
      projectId: _stringField(json, 'projectId'),
      branches: _stringListField(json, 'branches'),
      localBranches: _stringListField(json, 'localBranches'),
    );
  }
}

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.projectId,
    required this.name,
    required this.path,
    this.branch,
  });

  final String id;
  final String projectId;
  final String name;
  final String path;
  final String? branch;

  factory WorkspaceSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceSummary(
      id: _stringField(json, 'id'),
      projectId: _stringField(json, 'projectId'),
      name: _stringField(json, 'name'),
      path: _stringField(json, 'path'),
      branch: _optionalStringField(json, 'branch'),
    );
  }
}

class WorkspaceTabSummary {
  const WorkspaceTabSummary({
    required this.id,
    required this.workspaceId,
    required this.kind,
    required this.title,
    required this.payload,
  });

  final String id;
  final String workspaceId;
  final String kind;
  final String title;
  final Map<String, Object?> payload;

  factory WorkspaceTabSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceTabSummary(
      id: _stringField(json, 'id'),
      workspaceId: _stringField(json, 'workspaceId'),
      kind: _stringField(json, 'kind'),
      title: _stringField(json, 'title'),
      payload: _mapField(json, 'payload'),
    );
  }
}

class MobileTerminalAttachment {
  const MobileTerminalAttachment({
    required this.sessionId,
    required this.created,
    required this.running,
    required this.snapshot,
  });

  final String sessionId;
  final bool created;
  final bool running;
  final List<int> snapshot;

  factory MobileTerminalAttachment.fromJson(Map<String, Object?> json) {
    return MobileTerminalAttachment(
      sessionId: _stringField(json, 'sessionId'),
      created: json['created'] == true,
      running: json['running'] == true,
      snapshot: _bytesField(json, 'snapshotBase64'),
    );
  }
}

class MobileTerminalSession {
  const MobileTerminalSession({required this.tab, required this.attachment});

  final WorkspaceTabSummary tab;
  final MobileTerminalAttachment attachment;

  factory MobileTerminalSession.fromJson(Map<String, Object?> json) {
    return MobileTerminalSession(
      tab: WorkspaceTabSummary.fromJson(_mapField(json, 'tab')),
      attachment: MobileTerminalAttachment.fromJson(
        _mapField(json, 'attachment'),
      ),
    );
  }
}

String _stringField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key Is Required');
}

String? _optionalStringField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

int _intField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('$key Is Required');
}

DateTime? _optionalDateTimeField(Map<String, Object?> json, String key) {
  final value = _optionalStringField(json, key);
  if (value == null) {
    return null;
  }
  return DateTime.parse(value);
}

List<Object?> _listField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

List<String> _stringListField(Map<String, Object?> json, String key) {
  return <String>[
    for (final item in _listField(json, key))
      if (item is String) item,
  ];
}

Map<String, Object?> _mapField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return _dynamicMap(value);
  }
  return const <String, Object?>{};
}

Map<String, Object?> _dynamicMap(Map<dynamic, dynamic> value) {
  return Map<String, Object?>.from(value);
}

List<int> _bytesField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    return const <int>[];
  }
  return base64Decode(value);
}
