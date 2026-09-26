String? emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The SSH port typed into the editor: 22 when the field is blank, null when
/// the text is not a valid port.
int? parseRemoteHostPort(String text) {
  final value = text.trim();
  if (value.isEmpty) {
    return 22;
  }
  final port = int.tryParse(value);
  return port == null || port < 1 || port > 65535 ? null : port;
}

String normalizedRemoteHostPlatform(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'darwin' || 'mac' || 'macos' => 'macos',
    'linux' => 'linux',
    'win32' || 'windows' || 'windows_nt' => 'windows',
    _ => '',
  };
}

String normalizedRemoteHostArch(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'x86_64' || 'amd64' || 'x64' => 'x64',
    'aarch64' || 'arm64' => 'arm64',
    _ => '',
  };
}
