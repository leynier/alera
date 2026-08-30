part of 'alera_debug.dart';

final class const _Options({
  required final String cargoExecutable,
  required final String flutterExecutable,
  required final String device,
  required final String flavor,
  required final String appId,
  required final String bundleDir,
  required final String debugToken,
  required final String hostEmptyShutdownSeconds,
  required final String hostDetachedShutdownSeconds,
  required final String hostScrollbackBytes,
  required final String? appSupportDir,
}) {
  factory parse(List<String> arguments) {
    final map = <String, String>{};
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        map[argument.substring(2, equals)] = argument.substring(equals + 1);
        continue;
      }
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for $argument');
      }
      map[argument.substring(2)] = arguments[index + 1];
      index += 1;
    }
    final flavor =
        map['alera-flavor'] ??
        Platform.environment['ALERA_FLAVOR'] ??
        kAleraDevFlavor;
    final defaultAppId = flavor == kAleraReleaseFlavor
        ? kAleraReleaseBundleId
        : kAleraDevBundleId;
    return _Options(
      cargoExecutable: map['cargo'] ?? Platform.environment['CARGO'] ?? 'cargo',
      flutterExecutable:
          map['flutter'] ?? Platform.environment['FLUTTER'] ?? 'flutter',
      device:
          map['device'] ??
          Platform.environment['APP_DEVICE'] ??
          _defaultFlutterDevice(),
      flavor: flavor,
      appId:
          map['app-id'] ?? Platform.environment['ALERA_APP_ID'] ?? defaultAppId,
      bundleDir:
          map['bundle-dir'] ??
          Platform.environment['ALERA_CLI_BUNDLE_DIR'] ??
          '.dart_tool/alera',
      debugToken:
          map['debug-token'] ??
          Platform.environment['ALERA_CLI_DEBUG_TOKEN'] ??
          'dev-token',
      hostEmptyShutdownSeconds:
          map['host-empty-shutdown-seconds'] ??
          Platform.environment['ALERA_HOST_EMPTY_SHUTDOWN_SECONDS'] ??
          '30',
      hostDetachedShutdownSeconds:
          map['host-detached-shutdown-seconds'] ??
          Platform.environment['ALERA_HOST_DETACHED_SHUTDOWN_SECONDS'] ??
          '3600',
      hostScrollbackBytes:
          map['host-scrollback-bytes'] ??
          Platform.environment['ALERA_HOST_SCROLLBACK_BYTES'] ??
          '10000000',
      appSupportDir:
          map['app-support-dir'] ??
          Platform.environment['ALERA_APP_SUPPORT_DIR'],
    );
  }
}

String _defaultFlutterDevice() {
  if (Platform.isMacOS) {
    return 'macos';
  }
  if (Platform.isWindows) {
    return 'windows';
  }
  if (Platform.isLinux) {
    return 'linux';
  }
  throw const FormatException(
    'No default Flutter desktop device is available for this host platform. '
    'Pass --device explicitly.',
  );
}

final class const _RuntimePaths({
  required final Directory runtimeDir,
  required final File controlFile,
});

final class const _ProcessInfo({
  required final int pid,
  required final String commandLine,
});
