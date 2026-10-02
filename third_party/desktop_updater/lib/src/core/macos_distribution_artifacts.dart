import "dart:io";

import "package:desktop_updater/src/macos_update.dart";
import "package:path/path.dart" as path;

/// Assesses a DMG primary signature with Gatekeeper.
Future<void> verifyDmgPrimarySignature(
  File dmg, {
  ProcessRunner runProcess = defaultProcessRunner,
}) {
  return MacOSDistributionVerifier(runProcess: runProcess)
      .verifyDmgPrimarySignature(dmg);
}

/// Attaches a DMG read-only and returns the mounted volume metadata.
Future<MountedDmg> mountDmgReadOnly(
  File dmg, {
  ProcessRunner runProcess = defaultProcessRunner,
  Directory? mountPoint,
}) {
  return MacOSDistributionVerifier(runProcess: runProcess).mountDmgReadOnly(
    dmg: dmg,
    mountPoint: mountPoint,
  );
}

/// Detaches a mounted DMG volume.
Future<void> detachDmg(
  MountedDmg mounted, {
  ProcessRunner runProcess = defaultProcessRunner,
  ProcessRunner? cleanupProcess,
}) {
  return MacOSDistributionVerifier(
    runProcess: runProcess,
    cleanupProcess: cleanupProcess ?? runProcess,
  ).detachDmg(mounted);
}

/// Copies the configured `.app` from a mounted DMG into [destinationParent].
Future<Directory> copyAppFromMountedDmg({
  required MountedDmg mounted,
  required String appBundleName,
  required Directory destinationParent,
  ProcessRunner runProcess = defaultProcessRunner,
}) {
  return MacOSDistributionVerifier(runProcess: runProcess)
      .copyAppFromMountedDmg(
    mounted: mounted,
    appBundleName: appBundleName,
    destinationParent: destinationParent,
  );
}

/// Verifies a PKG installer and confirms expected package identifiers.
Future<void> verifyPkgInstaller({
  required File pkg,
  required List<String> expectedPackageIds,
  ProcessRunner runProcess = defaultProcessRunner,
  Future<Directory> Function() createTempDirectory =
      _defaultCreateTempDirectory,
}) {
  return MacOSDistributionVerifier(
    runProcess: runProcess,
    createTempDirectory: createTempDirectory,
  ).verifyPkgInstaller(
    pkg: pkg,
    expectedPackageIds: expectedPackageIds,
  );
}

/// Mounted macOS disk image information.
class MountedDmg {
  /// Creates mounted DMG metadata.
  const MountedDmg({
    required this.imagePath,
    required this.mountPoint,
    this.ownedMountPoint,
  });

  /// Source disk image path.
  final String imagePath;

  /// Mounted volume path.
  final String mountPoint;

  /// Temporary mountpoint owned by the updater, when one was supplied.
  final String? ownedMountPoint;
}

/// Verifies and stages macOS DMG and PKG distribution artifacts.
class MacOSDistributionVerifier {
  /// Creates a verifier with injectable command and temp-directory seams.
  const MacOSDistributionVerifier({
    this.runProcess = defaultProcessRunner,
    ProcessRunner? cleanupProcess,
    this.createTempDirectory = _defaultCreateTempDirectory,
  }) : cleanupProcess = cleanupProcess ?? runProcess;

  /// Process runner used for macOS system tools.
  final ProcessRunner runProcess;

  /// Process runner used for cleanup commands after cancellation.
  ///
  /// Cleanup must remain available after the operation token is canceled so
  /// mounted volumes do not outlive a failed update.
  final ProcessRunner cleanupProcess;

  /// Creates a temporary parent directory for expanded package metadata.
  final Future<Directory> Function() createTempDirectory;

  /// Assesses a DMG primary signature with Gatekeeper.
  Future<void> verifyDmgPrimarySignature(File dmg) {
    return _runChecked("/usr/sbin/spctl", [
      "--assess",
      "--type",
      "open",
      "--context",
      "context:primary-signature",
      "--verbose=2",
      dmg.path,
    ]);
  }

  /// Verifies a DMG when configured, then attaches it read-only.
  Future<MountedDmg> mountVerifiedDmg({
    required File dmg,
    required bool verifyPrimarySignature,
    Directory? mountPoint,
  }) async {
    if (verifyPrimarySignature) {
      await verifyDmgPrimarySignature(dmg);
    }
    return mountDmgReadOnly(dmg: dmg, mountPoint: mountPoint);
  }

  /// Attaches a DMG read-only and returns the mounted volume metadata.
  Future<MountedDmg> mountDmgReadOnly({
    required File dmg,
    Directory? mountPoint,
  }) async {
    if (mountPoint != null) {
      await mountPoint.create(recursive: true);
    }
    final arguments = ["attach", "-readonly", "-nobrowse"];
    if (mountPoint != null) {
      arguments.addAll(["-mountpoint", mountPoint.path]);
    }
    arguments.add(dmg.path);

    try {
      final result = await _runChecked("/usr/bin/hdiutil", arguments);
      return MountedDmg(
        imagePath: dmg.path,
        mountPoint:
            mountPoint?.path ?? _parseMountPoint(result.stdout.toString()),
        ownedMountPoint: mountPoint?.path,
      );
    } on Object catch (error, stackTrace) {
      if (mountPoint != null) {
        final mounted = MountedDmg(
          imagePath: dmg.path,
          mountPoint: mountPoint.path,
          ownedMountPoint: mountPoint.path,
        );
        try {
          await _detachWithFallback(mounted);
        } on Object {
          // The attach process can fail before a volume exists.
        }
        await _deleteOwnedMountPoint(mounted);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Mounts a verified DMG for [body] and always detaches it afterward.
  Future<T> withMountedVerifiedDmg<T>({
    required File dmg,
    required bool verifyPrimarySignature,
    Directory? mountPoint,
    required Future<T> Function(MountedDmg mounted) body,
  }) async {
    final mounted = await mountVerifiedDmg(
      dmg: dmg,
      verifyPrimarySignature: verifyPrimarySignature,
      mountPoint: mountPoint,
    );
    var bodyFailed = false;
    try {
      return await body(mounted);
    } catch (error) {
      bodyFailed = true;
      rethrow;
    } finally {
      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      try {
        await _detachWithFallback(mounted);
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      } finally {
        await _deleteOwnedMountPoint(mounted);
      }
      if (cleanupError != null && !bodyFailed) {
        Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
      }
    }
  }

  /// Detaches a mounted DMG volume.
  Future<void> detachDmg(MountedDmg mounted) {
    return _runChecked(
      "/usr/bin/hdiutil",
      ["detach", mounted.mountPoint],
      processRunner: cleanupProcess,
    );
  }

  Future<void> _detachWithFallback(MountedDmg mounted) async {
    try {
      await detachDmg(mounted);
      return;
    } on Object catch (error, stackTrace) {
      if (mounted.ownedMountPoint == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    await _runChecked(
      "/usr/bin/hdiutil",
      ["detach", "-force", mounted.mountPoint],
      processRunner: cleanupProcess,
    );
  }

  /// Copies the configured `.app` from a mounted DMG into [destinationParent].
  Future<Directory> copyAppFromMountedDmg({
    required MountedDmg mounted,
    required String appBundleName,
    required Directory destinationParent,
  }) async {
    final source = Directory(path.join(mounted.mountPoint, appBundleName));
    final destination = Directory(
      path.join(destinationParent.path, appBundleName),
    );
    await _runChecked("/usr/bin/ditto", [source.path, destination.path]);
    return destination;
  }

  /// Verifies a PKG installer and confirms expected package identifiers.
  Future<void> verifyPkgInstaller({
    required File pkg,
    required List<String> expectedPackageIds,
  }) async {
    await _runChecked("/usr/sbin/pkgutil", ["--check-signature", pkg.path]);
    await _runChecked("/usr/sbin/spctl", [
      "--assess",
      "--type",
      "install",
      "--verbose=2",
      pkg.path,
    ]);
    await _runChecked("/usr/bin/xcrun", ["stapler", "validate", pkg.path]);
    final expandedParent = await createTempDirectory();
    final expanded = Directory(path.join(expandedParent.path, "expanded"));
    try {
      await _runChecked("/usr/sbin/pkgutil", [
        "--expand-full",
        pkg.path,
        expanded.path,
      ]);
      await _verifyExpectedPackageIdsFromExpandedPkg(
        expanded: expanded,
        expectedPackageIds: expectedPackageIds,
      );
    } finally {
      if (await expandedParent.exists()) {
        await expandedParent.delete(recursive: true);
      }
    }
  }

  Future<ProcessResult> _runChecked(
    String executable,
    List<String> arguments, {
    ProcessRunner? processRunner,
  }) async {
    final result = await (processRunner ?? runProcess)(executable, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        "${result.stdout}${result.stderr}",
        result.exitCode,
      );
    }
    return result;
  }
}

Future<void> _deleteOwnedMountPoint(MountedDmg mounted) async {
  final ownedMountPoint = mounted.ownedMountPoint;
  if (ownedMountPoint == null) {
    return;
  }
  final directory = Directory(ownedMountPoint);
  try {
    if (await directory.exists()) {
      await directory.delete();
    }
  } on FileSystemException {
    // A still-mounted volume or a failed attach can keep the directory busy.
  }
}

Future<Directory> _defaultCreateTempDirectory() {
  return Directory.systemTemp.createTemp("desktop_updater_pkg_expand_");
}

String _parseMountPoint(String hdiutilOutput) {
  for (final line in hdiutilOutput.split("\n").reversed) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) {
      continue;
    }
    final columns = trimmed.split("\t");
    final mountPoint = columns.isEmpty ? "" : columns.last.trim();
    if (mountPoint.startsWith("/Volumes/")) {
      return mountPoint;
    }
    final match = RegExp(r"(/Volumes/.+)$").firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
  }
  throw StateError("hdiutil attach output did not contain a mount point.");
}

Future<void> _verifyExpectedPackageIdsFromExpandedPkg({
  required Directory expanded,
  required List<String> expectedPackageIds,
}) async {
  final actualPackageIds = await _collectPackageIds(expanded);
  for (final expected in expectedPackageIds) {
    if (!actualPackageIds.contains(expected)) {
      throw StateError(
        "Expanded PKG metadata did not contain expected package identifier "
        "$expected.",
      );
    }
  }
}

Future<Set<String>> _collectPackageIds(Directory expanded) async {
  final packageIds = <String>{};
  if (!await expanded.exists()) {
    return packageIds;
  }
  await for (final entity in expanded.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final name = path.basename(entity.path);
    if (name != "PackageInfo" && name != "Distribution") {
      continue;
    }
    final contents = await entity.readAsString();
    if (name == "PackageInfo") {
      packageIds.addAll(
        _collectTagAttributeValues(contents, "pkg-info", "identifier"),
      );
    } else {
      packageIds.addAll(
        _collectTagAttributeValues(contents, "pkg-ref", "id"),
      );
    }
  }
  return packageIds;
}

Iterable<String> _collectTagAttributeValues(
  String xml,
  String tag,
  String attribute,
) {
  final pattern = RegExp('<$tag\\b[^>]*\\b$attribute="([^"]+)"');
  return [
    for (final match in pattern.allMatches(xml)) match.group(1)!,
  ];
}
