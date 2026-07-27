import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';

typedef DesktopUpdateArtifactPreferences =
    Future<List<String>> Function(String platform, AleraUpdateChannel channel);

Future<List<String>> loadDesktopUpdateArtifactPreferences(
  String platform,
  AleraUpdateChannel channel,
) async {
  return switch (platform) {
    'macos' || 'windows' => const <String>['tar.gz'],
    'linux' when channel == AleraUpdateChannel.rc => const <String>['tar.gz'],
    'linux' => _linuxPackagePreference(),
    _ => const <String>[],
  };
}

Future<List<String>> _linuxPackagePreference() async {
  final osRelease = File('/etc/os-release');
  if (!await osRelease.exists()) {
    return const <String>[];
  }
  final installerKind = linuxInstallerKindFromOsRelease(
    await osRelease.readAsString(),
  );
  return installerKind == null ? const <String>[] : <String>[installerKind];
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
  if (_containsLinuxFamily(family, const <String>[
    'fedora',
    'rhel',
    'centos',
    'rocky',
    'almalinux',
    'suse',
    'opensuse',
  ])) {
    return 'rpm';
  }
  return null;
}

bool _containsLinuxFamily(String source, List<String> families) {
  final words = source.split(RegExp(r'\s+')).toSet();
  return families.any(words.contains);
}
