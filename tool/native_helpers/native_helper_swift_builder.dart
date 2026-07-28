import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'native_helper_derivation.dart';
import 'native_helper_manifest.dart';

typedef NativeHelperPinnedSourceResolver =
    Future<File> Function(
      String id,
      Uri sourceUrl,
      String sourceSha256,
      Directory cache,
      bool offline,
    );

final class NativeHelperSwiftBuilder {
  NativeHelperSwiftBuilder({
    required this.repositoryRoot,
    required this.sourceResolver,
  });

  final Directory repositoryRoot;
  final NativeHelperPinnedSourceResolver sourceResolver;

  Future<Uint8List> build({
    required NativeHelperAsset asset,
    required NativeHelperDerivation derivation,
    required File source,
    required Directory cache,
    required bool offline,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        '${asset.id} can only be derived with the macOS Swift toolchain.',
      );
    }
    final patch = File(
      p.join(repositoryRoot.path, p.fromUri(derivation.patchPath)),
    );
    if (!patch.existsSync() ||
        await _fileSha256(patch) != derivation.patchSha256) {
      throw StateError(
        '${asset.id} derivation patch is missing or does not match '
        '${derivation.patchSha256}.',
      );
    }

    final work = await cache.absolute.parent.createTemp(
      'derive-${asset.id}-${asset.sourceSha256.substring(0, 12)}-',
    );
    try {
      final sourceRoot = Directory(p.join(work.path, 'source'))
        ..createSync(recursive: true);
      await _extractArchiveSelection(
        source: source,
        destinationRoot: sourceRoot,
        archiveRoot: derivation.sourceArchiveRoot,
        selectedSubdirectory: derivation.sourceSubdirectory,
        destinationPrefix: '',
        preserveArchiveRelativePath: true,
      );
      for (final dependency in derivation.dependencies) {
        final dependencySource = await sourceResolver(
          '${asset.id}/${dependency.id}',
          dependency.sourceUrl,
          dependency.sourceSha256,
          cache,
          offline,
        );
        await _extractArchiveSelection(
          source: dependencySource,
          destinationRoot: sourceRoot,
          archiveRoot: dependency.archiveRoot,
          selectedSubdirectory: '.',
          destinationPrefix: dependency.destination,
          preserveArchiveRelativePath: false,
        );
      }

      final dependencyLock = File(
        p.join(sourceRoot.path, p.fromUri(derivation.dependencyLockPath)),
      );
      if (!dependencyLock.existsSync() ||
          await _fileSha256(dependencyLock) !=
              derivation.dependencyLockSha256) {
        throw StateError(
          '${asset.id} Swift dependency lock does not match '
          '${derivation.dependencyLockSha256}.',
        );
      }
      for (final target in derivation.patchTargets) {
        await _verifyPatchTarget(
          asset: asset,
          sourceRoot: sourceRoot,
          target: target,
          expectedSha256: target.beforeSha256,
          stage: 'before patching',
        );
      }

      final patchArguments = <String>[
        '-f',
        '-p1',
        '-F',
        '0',
        '-i',
        patch.absolute.path,
      ];
      final patchResult = await Process.run(
        '/usr/bin/patch',
        patchArguments,
        workingDirectory: sourceRoot.path,
      );
      if (patchResult.exitCode != 0) {
        throw ProcessException(
          '/usr/bin/patch',
          patchArguments,
          '${patchResult.stdout}\n${patchResult.stderr}',
          patchResult.exitCode,
        );
      }
      for (final target in derivation.patchTargets) {
        await _verifyPatchTarget(
          asset: asset,
          sourceRoot: sourceRoot,
          target: target,
          expectedSha256: target.afterSha256,
          stage: 'after patching',
        );
      }

      final scratch = Directory(p.join(work.path, 'swift-build'))
        ..createSync(recursive: true);
      final arguments = <String>[
        'swift',
        'build',
        '-c',
        'release',
        '--product',
        derivation.product,
        for (final architecture in derivation.architectures) ...<String>[
          '--arch',
          architecture,
        ],
        '--build-path',
        scratch.path,
      ];
      await _runStreamingProcess(
        'xcrun',
        arguments,
        workingDirectory: p.join(
          sourceRoot.path,
          p.fromUri(derivation.packageDirectory),
        ),
      );
      final payload = File(
        p.join(scratch.path, p.fromUri(derivation.buildOutput)),
      );
      if (!payload.existsSync()) {
        throw StateError(
          '${asset.id} Swift build did not produce ${payload.path}.',
        );
      }
      await _runStreamingProcess('/usr/bin/codesign', <String>[
        '--sign',
        '-',
        '--force',
        payload.path,
      ]);
      await _runStreamingProcess('/usr/bin/lipo', <String>[
        payload.path,
        '-verify_arch',
        ...derivation.architectures,
      ]);
      return payload.readAsBytes();
    } finally {
      if (work.existsSync()) {
        await work.delete(recursive: true);
      }
    }
  }

  Future<void> _extractArchiveSelection({
    required File source,
    required Directory destinationRoot,
    required String archiveRoot,
    required String selectedSubdirectory,
    required String destinationPrefix,
    required bool preserveArchiveRelativePath,
  }) async {
    final sourceBytes = await source.readAsBytes();
    final tarBytes = const GZipDecoder().decodeBytes(sourceBytes, verify: true);
    final archive = TarDecoder().decodeBytes(tarBytes, verify: true);
    var extractedFiles = 0;
    for (final entry in archive.files) {
      final normalizedName = p.posix.normalize(entry.name);
      if (p.posix.isAbsolute(entry.name) ||
          normalizedName == '..' ||
          normalizedName.startsWith('../')) {
        throw StateError('Archive contains an unsafe path: ${entry.name}');
      }
      if (normalizedName == archiveRoot) {
        continue;
      }
      final archivePrefix = '$archiveRoot/';
      if (!normalizedName.startsWith(archivePrefix)) {
        continue;
      }
      final archiveRelative = normalizedName.substring(archivePrefix.length);
      final selected =
          selectedSubdirectory == '.' ||
          archiveRelative == selectedSubdirectory ||
          archiveRelative.startsWith('$selectedSubdirectory/');
      if (!selected) {
        continue;
      }
      final selectedRelative =
          !preserveArchiveRelativePath && selectedSubdirectory != '.'
          ? p.posix.relative(archiveRelative, from: selectedSubdirectory)
          : archiveRelative;
      final relativeOutput = p.posix.join(destinationPrefix, selectedRelative);
      final destination = p.joinAll(<String>[
        destinationRoot.path,
        ...p.posix.split(relativeOutput),
      ]);
      if (entry.isDirectory) {
        await Directory(destination).create(recursive: true);
        continue;
      }
      if (!entry.isFile) {
        throw StateError(
          'Selected archive path is not a regular file: ${entry.name}',
        );
      }
      final file = File(destination);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content, flush: true);
      extractedFiles += 1;
    }
    if (extractedFiles == 0) {
      throw StateError(
        'Archive $source did not contain $archiveRoot/'
        '$selectedSubdirectory.',
      );
    }
  }

  Future<void> _verifyPatchTarget({
    required NativeHelperAsset asset,
    required Directory sourceRoot,
    required NativeHelperPatchTarget target,
    required String expectedSha256,
    required String stage,
  }) async {
    final file = File(p.join(sourceRoot.path, p.fromUri(target.path)));
    if (!file.existsSync()) {
      throw StateError(
        '${asset.id} patch target is missing $stage: ${target.path}.',
      );
    }
    final actual = await _fileSha256(file);
    if (actual != expectedSha256) {
      throw StateError(
        '${asset.id} patch target ${target.path} has SHA-256 $actual '
        '$stage, expected $expectedSha256.',
      );
    }
  }
}

Future<void> _runStreamingProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final stdoutDone = stdout.addStream(process.stdout);
  final stderrDone = stderr.addStream(process.stderr);
  final processExitCode = await process.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  if (processExitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Native helper command failed.',
      processExitCode,
    );
  }
}

Future<String> _fileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
