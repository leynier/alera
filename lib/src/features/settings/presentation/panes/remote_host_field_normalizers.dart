String? emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
