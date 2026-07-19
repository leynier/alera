import 'dart:io';

void validatePairingEndpoint(String endpoint) {
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
