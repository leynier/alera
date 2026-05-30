part of 'alera_debug.dart';

final class _Options {
  const _Options({
    required this.dartExecutable,
    required this.cargoExecutable,
    required this.flutterExecutable,
    required this.device,
    required this.flavor,
    required this.appId,
    required this.bundleDir,
    required this.debugPort,
    required this.debugToken,
    required this.hostEmptyShutdownSeconds,
    required this.hostDetachedShutdownSeconds,
    required this.hostScrollbackBytes,
    required this.appSupportDir,
  });

  factory _Options.parse(List<String> arguments) {
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
      dartExecutable: map['dart'] ?? Platform.environment['DART'] ?? 'dart',
      cargoExecutable:
          map['cargo'] ?? Platform.environment['CARGO'] ?? 'cargo',
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
      debugPort:
          map['debug-port'] ??
          Platform.environment['ALERA_CLI_DEBUG_PORT'] ??
          '8181',
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

  final String dartExecutable;
  final String cargoExecutable;
  final String flutterExecutable;
  final String device;
  final String flavor;
  final String appId;
  final String bundleDir;
  final String debugPort;
  final String debugToken;
  final String hostEmptyShutdownSeconds;
  final String hostDetachedShutdownSeconds;
  final String hostScrollbackBytes;
  final String? appSupportDir;
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

final class _RuntimePaths {
  const _RuntimePaths({required this.runtimeDir, required this.controlFile});

  final Directory runtimeDir;
  final File controlFile;
}

final class _ProcessInfo {
  const _ProcessInfo({required this.pid, required this.commandLine});

  final int pid;
  final String commandLine;
}
