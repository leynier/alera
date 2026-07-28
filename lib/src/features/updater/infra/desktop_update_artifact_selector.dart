import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';

typedef DesktopUpdateArtifactPreferences =
    Future<List<String>> Function(String platform, AleraUpdateChannel channel);

Future<List<String>> loadDesktopUpdateArtifactPreferences(
  String platform,
  AleraUpdateChannel channel,
) async {
  if (platform != 'linux') {
    return desktopUpdateArtifactPreferences(
      platform: platform,
      channel: channel,
    );
  }
  return desktopUpdateArtifactPreferences(
    platform: platform,
    channel: channel,
    linuxOsRelease: await _readLinuxOsRelease(),
  );
}

Future<String?> _readLinuxOsRelease() async {
  final osRelease = File('/etc/os-release');
  if (!await osRelease.exists()) {
    return null;
  }
  return osRelease.readAsString();
}

List<String> desktopUpdateArtifactPreferences({
  required String platform,
  required AleraUpdateChannel channel,
  String? linuxOsRelease,
}) {
  return switch ((platform, channel)) {
    ('macos' || 'windows', _) => const <String>['tar.gz'],
    ('linux', _) => switch (linuxInstallerKindFromOsRelease(
      linuxOsRelease ?? '',
    )) {
      final installerKind? => <String>[installerKind],
      null => const <String>[],
    },
    _ => const <String>[],
  };
}

String? linuxInstallerKindFromOsRelease(String source) {
  final values = <String, String>{};
  for (final line in source.split('\n')) {
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = line.substring(0, separator).trim().toUpperCase();
    final value = line
        .substring(separator + 1)
        .trim()
        .replaceAll(RegExp(r'^"|"$'), '')
        .toLowerCase();
    values[key] = value;
  }
  final family = '${values['ID'] ?? ''} ${values['ID_LIKE'] ?? ''}';
  if (_containsLinuxFamily(family, const <String>[
    'debian',
    'ubuntu',
    'mint',
    'pop',
  ])) {
    return 'deb';
  }
  // openSUSE is deliberately absent: the published spec declares Fedora
  // dependency names (mpv-libs, webkit2gtk4.1, gtk3) that openSUSE provides
  // under different names, so offering the rpm there promises an update whose
  // transaction can never resolve.
  if (_containsLinuxFamily(family, const <String>[
    'fedora',
    'rhel',
    'centos',
    'rocky',
    'almalinux',
  ])) {
    return 'rpm';
  }
  return null;
}

bool _containsLinuxFamily(String source, List<String> families) {
  final words = source.split(RegExp(r'\s+')).toSet();
  return families.any(words.contains);
}
