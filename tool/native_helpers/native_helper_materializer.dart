import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'native_helper_derivation.dart';
import 'native_helper_manifest.dart';
import 'native_helper_swift_builder.dart';

typedef NativeHelperDownloader = Future<void> Function(Uri source, File output);
typedef NativeHelperDerivedPayloadBuilder =
    Future<Uint8List> Function({
      required NativeHelperAsset asset,
      required NativeHelperDerivation derivation,
      required File source,
      required Directory cache,
      required bool offline,
    });

final class NativeHelperMaterializer {
  NativeHelperMaterializer({
    required this.repositoryRoot,
    required this.manifest,
    NativeHelperDownloader? downloader,
    this.derivedPayloadBuilder,
  }) : _downloader = downloader ?? downloadNativeHelper;

  final Directory repositoryRoot;
  final NativeHelperManifest manifest;
  final NativeHelperDownloader _downloader;
  final NativeHelperDerivedPayloadBuilder? derivedPayloadBuilder;

  Future<void> prepare({
    required String platform,
    required Directory output,
    required Directory cache,
    bool offline = false,
  }) async {
    final normalized = normalizeNativeHelperPlatform(platform);
    final assets = manifest.assetsFor(normalized);
    if (assets.isEmpty) {
      throw StateError('No native helpers are declared for $normalized.');
    }
    final noticeSource = Directory(
      p.join(repositoryRoot.path, p.fromUri(manifest.noticeDirectory)),
    );
    _verifyNotices(noticeSource, assets);
    await cache.create(recursive: true);
    await output.parent.create(recursive: true);
    var canReusePreparedPayloads = false;
    if (output.existsSync()) {
      try {
        await verifyNativeHelperBundle(
          platform: normalized,
          emulatorRoot: output,
          expected: manifest,
        );
        canReusePreparedPayloads = true;
      } catch (_) {
        canReusePreparedPayloads = false;
      }
    }
    final staging = Directory(
      '${output.path}.staging-$pid-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);
    try {
      final payloadSha256ById = <String, String>{};
      for (final asset in assets) {
        final preparedPayload = File(
          p.join(output.path, p.fromUri(asset.relativePath)),
        );
        // Derived payload hashes live beside the payload, so only independently
        // hash-pinned assets are safe to reuse without rebuilding.
        final payload = canReusePreparedPayloads && asset.derivation == null
            ? await preparedPayload.readAsBytes()
            : await _materializePayload(asset, cache, offline: offline);
        final payloadDigest = sha256.convert(payload).toString();
        final expectedPayloadDigest = asset.payloadSha256;
        if (expectedPayloadDigest != null &&
            payloadDigest != expectedPayloadDigest) {
          throw StateError(
            '${asset.id} payload SHA-256 mismatch: expected '
            '$expectedPayloadDigest, got $payloadDigest.',
          );
        }
        payloadSha256ById[asset.id] = payloadDigest;
        final destination = File(
          p.join(staging.path, p.fromUri(asset.relativePath)),
        );
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(payload, flush: true);
        if (asset.executable && !Platform.isWindows) {
          final chmod = await Process.run('chmod', <String>[
            '755',
            destination.path,
          ]);
          if (chmod.exitCode != 0) {
            throw ProcessException(
              'chmod',
              <String>['755', destination.path],
              '${chmod.stderr}',
              chmod.exitCode,
            );
          }
        }
      }
      await _copyNotices(noticeSource, staging);
      final bundleManifest = File(p.join(staging.path, 'manifest.json'));
      await bundleManifest.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest.bundleJson(normalized, payloadSha256ById: payloadSha256ById))}\n',
        flush: true,
      );
      await _replaceManagedOutput(staging, output);
    } catch (_) {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<Uint8List> _materializePayload(
    NativeHelperAsset asset,
    Directory cache, {
    required bool offline,
  }) async {
    final source = await _obtainPinnedSource(
      id: asset.id,
      sourceUrl: asset.sourceUrl,
      sourceSha256: asset.sourceSha256,
      cache: cache,
      offline: offline,
    );
    final derivation = asset.derivation;
    if (derivation != null) {
      final builder = derivedPayloadBuilder;
      if (builder != null) {
        return builder(
          asset: asset,
          derivation: derivation,
          source: source,
          cache: cache,
          offline: offline,
        );
      }
      return NativeHelperSwiftBuilder(
        repositoryRoot: repositoryRoot,
        sourceResolver:
            (id, sourceUrl, sourceSha256, sourceCache, sourceOffline) =>
                _obtainPinnedSource(
                  id: id,
                  sourceUrl: sourceUrl,
                  sourceSha256: sourceSha256,
                  cache: sourceCache,
                  offline: sourceOffline,
                ),
      ).build(
        asset: asset,
        derivation: derivation,
        source: source,
        cache: cache,
        offline: offline,
      );
    }
    return _extractPayload(source, asset);
  }

  Future<File> _obtainPinnedSource({
    required String id,
    required Uri sourceUrl,
    required String sourceSha256,
    required Directory cache,
    required bool offline,
  }) async {
    final cached = File(p.join(cache.path, sourceSha256));
    if (cached.existsSync()) {
      if (await fileSha256(cached) == sourceSha256) {
        return cached;
      }
      await cached.delete();
    }
    if (offline) {
      throw StateError('$id is absent from the verified native helper cache.');
    }
    final pending = File(
      '${cached.path}.download-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await _downloader(sourceUrl, pending);
      final digest = await fileSha256(pending);
      if (digest != sourceSha256) {
        throw StateError(
          '$id source SHA-256 mismatch: expected '
          '$sourceSha256, got $digest.',
        );
      }
      try {
        await pending.rename(cached.path);
      } on FileSystemException {
        if (!cached.existsSync() || await fileSha256(cached) != sourceSha256) {
          rethrow;
        }
        await pending.delete();
      }
      return cached;
    } catch (_) {
      if (pending.existsSync()) {
        await pending.delete();
      }
      rethrow;
    }
  }

  Future<Uint8List> _extractPayload(
    File source,
    NativeHelperAsset asset,
  ) async {
    final archiveMember = asset.archiveMember;
    final sourceBytes = await source.readAsBytes();
    if (archiveMember == null) {
      return sourceBytes;
    }
    final tarBytes = const GZipDecoder().decodeBytes(sourceBytes, verify: true);
    final archive = TarDecoder().decodeBytes(tarBytes, verify: true);
    final matches = archive.files
        .where((entry) => entry.isFile && entry.name == archiveMember)
        .toList(growable: false);
    if (matches.length != 1) {
      throw StateError(
        '${asset.id} archive must contain exactly one $archiveMember.',
      );
    }
    return matches.single.content;
  }

  void _verifyNotices(Directory noticeSource, List<NativeHelperAsset> assets) {
    if (!File(p.join(noticeSource.path, 'NOTICE.md')).existsSync()) {
      throw StateError('Native helper NOTICE.md is missing.');
    }
    for (final asset in assets) {
      final license = File(
        p.join(noticeSource.path, p.fromUri(asset.licensePath)),
      );
      if (!license.existsSync()) {
        throw StateError('${asset.id} license is missing: ${license.path}');
      }
      for (final dependency
          in asset.derivation?.dependencies ??
              const <NativeHelperDependency>[]) {
        final dependencyLicense = File(
          p.join(noticeSource.path, p.fromUri(dependency.licensePath)),
        );
        if (!dependencyLicense.existsSync()) {
          throw StateError(
            '${asset.id}/${dependency.id} license is missing: '
            '${dependencyLicense.path}',
          );
        }
      }
    }
  }

  Future<void> _copyNotices(Directory source, Directory staging) async {
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: source.path);
      final destination = File(p.join(staging.path, relative));
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  Future<void> _replaceManagedOutput(
    Directory staging,
    Directory output,
  ) async {
    if (output.existsSync()) {
      final marker = File(p.join(output.path, 'manifest.json'));
      final containsNonDirectory = output
          .listSync(recursive: true, followLinks: false)
          .any((entity) => entity is! Directory);
      if (containsNonDirectory && !_isGeneratedBundle(marker)) {
        throw StateError(
          'Refusing to replace unmanaged native helper output: ${output.path}',
        );
      }
      await output.delete(recursive: true);
    }
    await staging.rename(output.path);
  }
}

Future<void> verifyNativeHelperBundle({
  required String platform,
  required Directory emulatorRoot,
  required NativeHelperManifest expected,
}) async {
  final normalized = normalizeNativeHelperPlatform(platform);
  final generatedFile = File(p.join(emulatorRoot.path, 'manifest.json'));
  if (!_isGeneratedBundle(generatedFile)) {
    throw StateError(
      'Missing generated native helper manifest: ${generatedFile.path}',
    );
  }
  final decoded = jsonDecode(generatedFile.readAsStringSync());
  final generated = decoded as Map<String, Object?>;
  if (generated['platform'] != normalized) {
    throw StateError(
      'Native helper bundle platform is ${generated['platform']}, '
      'expected $normalized.',
    );
  }
  final rawAssets = generated['assets'];
  if (rawAssets is! List<Object?>) {
    throw const FormatException(
      'Generated native helper assets must be an array.',
    );
  }
  final generatedById = <String, Map<String, Object?>>{};
  for (final value in rawAssets) {
    if (value is! Map<String, Object?> || value['id'] is! String) {
      throw const FormatException('Generated native helper asset is invalid.');
    }
    generatedById[value['id']! as String] = value;
  }
  final expectedAssets = expected.assetsFor(normalized);
  final expectedIds = expectedAssets.map((asset) => asset.id).toSet();
  if (generatedById.keys.toSet().difference(expectedIds).isNotEmpty ||
      expectedIds.difference(generatedById.keys.toSet()).isNotEmpty) {
    throw StateError(
      'Native helper bundle asset set does not match the source manifest.',
    );
  }
  for (final asset in expectedAssets) {
    final generatedAsset = generatedById[asset.id]!;
    final generatedSha256 = generatedAsset['sha256'];
    if (generatedSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(generatedSha256)) {
      throw StateError('${asset.id} bundle SHA-256 is invalid.');
    }
    if (generatedAsset['version'] != asset.version ||
        generatedAsset['relativePath'] != asset.relativePath ||
        generatedAsset['sourceSha256'] != asset.sourceSha256 ||
        generatedAsset['sourceCommit'] != asset.sourceCommit ||
        (asset.payloadSha256 != null &&
            generatedSha256 != asset.payloadSha256) ||
        jsonEncode(generatedAsset['derivation']) !=
            jsonEncode(asset.derivation?.bundleJson())) {
      throw StateError('${asset.id} bundle metadata does not match its pin.');
    }
    final payload = File(
      p.join(emulatorRoot.path, p.fromUri(asset.relativePath)),
    );
    if (!payload.existsSync()) {
      throw StateError('${asset.id} payload is missing: ${payload.path}');
    }
    final digest = await fileSha256(payload);
    if (digest != generatedSha256) {
      throw StateError(
        '${asset.id} installed SHA-256 mismatch: expected '
        '$generatedSha256, got $digest.',
      );
    }
    if (asset.executable &&
        normalized != 'windows' &&
        !Platform.isWindows &&
        payload.statSync().mode & 0x49 == 0) {
      throw StateError('${asset.id} is not executable: ${payload.path}');
    }
    final license = File(
      p.join(emulatorRoot.path, p.fromUri(asset.licensePath)),
    );
    if (!license.existsSync()) {
      throw StateError('${asset.id} installed license is missing.');
    }
    for (final dependency
        in asset.derivation?.dependencies ?? const <NativeHelperDependency>[]) {
      final dependencyLicense = File(
        p.join(emulatorRoot.path, p.fromUri(dependency.licensePath)),
      );
      if (!dependencyLicense.existsSync()) {
        throw StateError(
          '${asset.id}/${dependency.id} installed license is missing.',
        );
      }
    }
  }
  if (!File(p.join(emulatorRoot.path, 'NOTICE.md')).existsSync()) {
    throw StateError('Installed native helper NOTICE.md is missing.');
  }
}

Directory nativeHelperRootForBundle({
  required String platform,
  required Directory bundle,
}) {
  final normalized = normalizeNativeHelperPlatform(platform);
  if (normalized != 'macos') {
    return Directory(p.join(bundle.path, 'resources', 'alera', 'emulator'));
  }
  if (p.extension(bundle.path).toLowerCase() == '.app') {
    return Directory(
      p.join(bundle.path, 'Contents', 'Resources', 'alera', 'emulator'),
    );
  }
  for (final name in const <String>['Alera.app', 'alera.app']) {
    final candidate = Directory(p.join(bundle.path, name));
    if (candidate.existsSync()) {
      return Directory(
        p.join(candidate.path, 'Contents', 'Resources', 'alera', 'emulator'),
      );
    }
  }
  throw StateError('No macOS app bundle found under ${bundle.path}.');
}

Future<String> fileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<void> downloadNativeHelper(Uri source, File output) async {
  await output.parent.create(recursive: true);
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt += 1) {
    final client = HttpClient()
      ..findProxy = HttpClient.findProxyFromEnvironment
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = 'Alera native helper materializer';
    try {
      final request = await client.getUrl(source);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}.',
          uri: source,
        );
      }
      await response.pipe(output.openWrite());
      client.close();
      return;
    } catch (error) {
      lastError = error;
      client.close(force: true);
      if (output.existsSync()) {
        await output.delete();
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }
  throw StateError('Failed to download $source: $lastError');
}

bool _isGeneratedBundle(File marker) {
  if (!marker.existsSync()) {
    return false;
  }
  try {
    final decoded = jsonDecode(marker.readAsStringSync());
    return decoded is Map<String, Object?> &&
        decoded['generatedBy'] == nativeHelperBundleGenerator;
  } on FormatException {
    return false;
  }
}
