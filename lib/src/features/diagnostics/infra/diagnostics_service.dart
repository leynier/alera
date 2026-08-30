import 'dart:io';

import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/diagnostics/domain/diagnostics_bundle_metadata.dart';
import 'package:alera/src/features/diagnostics/infra/diagnostics_bundle_builder.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// Runtime facts the bundle records, read from `status.get`.
class const RuntimeDiagnosticsInfo({
  final String? version,
  final String? commit,
  final int? protocolVersion,
  this.logDirectory,
  final List<String> capabilities = const <String>[],
}) {
  /// Reported by hosts advertising `hostDiagnosticsLogsV1`. Absent on older
  /// hosts, which simply contribute no runtime logs to the bundle.
  final String? logDirectory;
}

/// Collects logs and metadata, and reveals the log folder.
class DiagnosticsService({
  final DiagnosticsBundleBuilder builder = const DiagnosticsBundleBuilder(),
  Future<bool> Function(Uri uri)? openUri,
  Future<PackageInfo> Function()? packageInfo,
  DateTime Function()? now,
}) {
  this
    : _openUri = openUri ?? _launchUri,
      _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
      _now = now ?? DateTime.now;

  final Future<bool> Function(Uri uri) _openUri;
  final Future<PackageInfo> Function() _packageInfo;
  final DateTime Function() _now;

  static Future<bool> _launchUri(Uri uri) => url_launcher.launchUrl(
    uri,
    mode: url_launcher.LaunchMode.platformDefault,
  );

  Directory? get appLogDirectory => AppLogger.logDirectory;

  /// Opens the app log folder in the platform file manager.
  Future<bool> revealAppLogDirectory() async {
    final directory = appLogDirectory;
    if (directory == null) {
      return false;
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return _openUri(.file(directory.path));
  }

  /// Builds the bundle bytes for the current machine.
  Future<List<int>> buildBundle({RuntimeDiagnosticsInfo? runtime}) async {
    // Pending writes must land first, or the bundle misses the very lines that
    // describe whatever the user is reporting.
    await AppLogger.flush();
    final info = await _packageInfo();
    final runtimeLogDirectory = runtime?.logDirectory;

    return builder.build(
      metadata: DiagnosticsBundleMetadata(
        appVersion: '${info.version}+${info.buildNumber}',
        flavor: kAleraFlavor,
        operatingSystem: Platform.operatingSystem,
        operatingSystemVersion: Platform.operatingSystemVersion,
        collectedAt: _now(),
        runtimeHostVersion: runtime?.version,
        runtimeHostCommit: runtime?.commit,
        protocolVersion: runtime?.protocolVersion,
        runtimeCapabilities: runtime?.capabilities ?? const <String>[],
      ),
      appLogDirectory: appLogDirectory,
      runtimeLogDirectory: runtimeLogDirectory == null
          ? null
          : Directory(runtimeLogDirectory),
    );
  }

  String suggestedFileName() =>
      DiagnosticsBundleBuilder.suggestedFileName(_now());
}
