/// Client-side mirror of the pairing endpoint rules enforced by the Rust
/// runtime (`rust/alera-cli/src/mobile_access.rs`). Pre-validating here gives
/// immediate feedback in the settings pane; the runtime remains the authority.
library;

bool isWildcardBindHost(String value) {
  return switch (value.trim()) {
    '0.0.0.0' || '::' || '[::]' => true,
    _ => false,
  };
}

bool isLoopbackEndpointHost(String host) {
  final normalized = _normalizeEndpointHost(host);
  if (normalized == 'localhost') {
    return true;
  }
  return _isLoopbackIpLiteral(normalized);
}

/// True when the host is an IP literal inside the Tailscale tailnet ranges
/// (IPv4 100.64.0.0/10 or IPv6 fd7a:115c:a1e0::/48). Mirrors the Rust
/// `is_tailscale_ip`.
bool isTailscaleEndpointHost(String host) {
  final normalized = _normalizeEndpointHost(host);
  try {
    final bytes = Uri.parseIPv4Address(normalized);
    return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127;
  } on FormatException {
    // Not an IPv4 literal; fall through to IPv6.
  }
  try {
    final bytes = Uri.parseIPv6Address(normalized);
    return bytes[0] == 0xfd &&
        bytes[1] == 0x7a &&
        bytes[2] == 0x11 &&
        bytes[3] == 0x5c &&
        bytes[4] == 0xa1 &&
        bytes[5] == 0xe0;
  } on FormatException {
    return false;
  }
}

String _normalizeEndpointHost(String host) {
  var normalized = host.trim();
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  while (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.toLowerCase();
}

bool _isLoopbackIpLiteral(String value) {
  try {
    final bytes = Uri.parseIPv4Address(value);
    return bytes[0] == 127;
  } on FormatException {
    // Not an IPv4 literal; fall through to IPv6.
  }
  try {
    final bytes = Uri.parseIPv6Address(value);
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] != 0) {
        return false;
      }
    }
    return bytes.last == 1;
  } on FormatException {
    return false;
  }
}

class MobilePairingEndpointParts {
  const MobilePairingEndpointParts({
    required this.scheme,
    required this.host,
    required this.port,
  });

  final String scheme;
  final String host;
  final int port;
}

/// Extracts scheme, host, and the explicit authority port. Returns null when
/// the value is not a ws:// or wss:// URL with a parsable authority. The port
/// must appear in the authority itself; a port-like value inside the query or
/// fragment does not count (mirrors the Rust `endpoint_port`).
MobilePairingEndpointParts? parseMobilePairingEndpoint(String endpoint) {
  final trimmed = endpoint.trim();
  final schemeSplit = trimmed.split('://');
  if (schemeSplit.length != 2) {
    return null;
  }
  final scheme = schemeSplit[0].toLowerCase();
  if (scheme != 'ws' && scheme != 'wss') {
    return null;
  }
  var authority = schemeSplit[1].split(RegExp('[/?#]')).first;
  final userInfoIndex = authority.lastIndexOf('@');
  if (userInfoIndex >= 0) {
    authority = authority.substring(userInfoIndex + 1);
  }
  String host;
  String portText;
  if (authority.startsWith('[')) {
    final closing = authority.indexOf(']');
    if (closing < 0) {
      return null;
    }
    host = authority.substring(0, closing + 1);
    final rest = authority.substring(closing + 1);
    if (!rest.startsWith(':')) {
      return null;
    }
    portText = rest.substring(1);
  } else {
    final colon = authority.lastIndexOf(':');
    if (colon < 0) {
      return null;
    }
    host = authority.substring(0, colon);
    portText = authority.substring(colon + 1);
  }
  if (host.trim().isEmpty) {
    return null;
  }
  final port = int.tryParse(portText);
  if (port == null) {
    return null;
  }
  return MobilePairingEndpointParts(scheme: scheme, host: host, port: port);
}

/// Validates a custom pairing endpoint, returning a user-facing error or null
/// when valid. Mirrors `validate_pairing_endpoint` plus the ws-port match rule
/// from `prepare_mobile_pairing_offer_settings`.
String? validateMobilePairingEndpoint({
  required String endpoint,
  required bool gatewayEnabled,
  required int gatewayPort,
}) {
  final parts = parseMobilePairingEndpoint(endpoint);
  if (parts == null) {
    return 'Endpoint must be a ws:// or wss:// URL with an explicit port';
  }
  if (parts.port < 1 || parts.port > 65535) {
    return 'Endpoint port must be between 1 and 65535';
  }
  if (parts.scheme == 'ws' &&
      !isLoopbackEndpointHost(parts.host) &&
      !isTailscaleEndpointHost(parts.host)) {
    return 'Endpoints outside loopback or a Tailscale Tailnet must use wss://';
  }
  if (parts.scheme == 'ws' && gatewayEnabled && parts.port != gatewayPort) {
    return 'ws:// endpoint port must match the enabled gateway port '
        '$gatewayPort';
  }
  return null;
}

/// Contextual hint for the gateway settings group, or null when no hint is
/// needed for the given bind host.
String? mobileGatewayBindHostHint({
  required String bindHost,
  required int port,
}) {
  if (isWildcardBindHost(bindHost)) {
    return 'Wildcard bind hosts require an explicit wss:// endpoint when '
        'linking (for example wss://<host-or-vpn-name>:$port)';
  }
  if (isTailscaleEndpointHost(bindHost)) {
    return 'Devices connect over your Tailnet - both devices must be signed '
        'in to Tailscale';
  }
  if (!isLoopbackEndpointHost(bindHost)) {
    return 'Devices outside this machine must connect through wss:// - use a '
        'TLS proxy or a VPN address and provide a custom endpoint';
  }
  return null;
}
