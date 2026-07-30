import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:http/http.dart' as http;

class DesktopUpdateIndexNotFound implements Exception {
  const DesktopUpdateIndexNotFound();
}

class DesktopUpdaterReleaseCandidate {
  const DesktopUpdaterReleaseCandidate({
    required this.version,
    required this.buildNumber,
    required this.generatedAt,
    required this.mandatory,
    required this.platform,
    required this.artifactKind,
    required this.artifactUrl,
    required this.artifactSha256,
    required this.artifactLength,
  });

  final String version;
  final int? buildNumber;
  final DateTime generatedAt;
  final bool mandatory;
  final String platform;
  final String artifactKind;
  final Uri artifactUrl;
  final String artifactSha256;
  final int artifactLength;
}

abstract interface class AleraDesktopUpdaterBackend {
  Future<DesktopUpdaterReleaseCandidate?> checkForUpdate({
    required Uri archiveUrl,
    required String channel,
    required String currentVersion,
    required String currentBuildNumber,
    required String platform,
    required bool requireSignature,
    required String publicKeyId,
    required String publicKeyBase64,
  });

  Future<String> downloadAndStage(
    DesktopUpdaterReleaseCandidate candidate, {
    void Function(double progress)? onProgress,
  });

  Future<void> install({
    required String stagingPath,
    required bool allowUnsignedMacOSUpdates,
  });

  void dispose();
}

class DesktopUpdaterBackend implements AleraDesktopUpdaterBackend {
  DesktopUpdaterBackend({DesktopUpdater? updater, http.Client? client})
    : _updater = updater ?? DesktopUpdater(),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final DesktopUpdater _updater;
  final http.Client _client;
  final bool _ownsClient;
  Uri? _archiveUrl;
  DesktopVersionInfo? _currentVersion;
  ReleaseDescriptor? _descriptor;
  DesktopUpdaterReleaseCandidate? _candidate;

  @override
  Future<DesktopUpdaterReleaseCandidate?> checkForUpdate({
    required Uri archiveUrl,
    required String channel,
    required String currentVersion,
    required String currentBuildNumber,
    required String platform,
    required bool requireSignature,
    required String publicKeyId,
    required String publicKeyBase64,
  }) async {
    final version = DesktopVersionInfo.fromParts(
      versionName: currentVersion,
      buildNumber: currentBuildNumber,
    );
    final indexResponse = await _client.get(archiveUrl);
    if (indexResponse.statusCode == HttpStatus.notFound) {
      _clearSelection();
      throw const DesktopUpdateIndexNotFound();
    }
    _requireSuccess(indexResponse, archiveUrl);
    final index = ReleaseIndex.fromJson(
      jsonDecode(indexResponse.body) as Map<String, dynamic>,
    );
    final item = selectReleaseIndexItem(
      index: index,
      platform: platform,
      channel: channel,
      currentVersion: version,
    );
    if (item == null) {
      _clearSelection();
      return null;
    }

    final descriptorResponse = await _client.get(item.release);
    _requireSuccess(descriptorResponse, item.release);
    final descriptor = ReleaseDescriptor.fromJson(
      jsonDecode(descriptorResponse.body) as Map<String, dynamic>,
    );
    _verifyDescriptorIdentity(
      descriptor: descriptor,
      item: item,
      platform: platform,
      channel: channel,
    );
    if (requireSignature) {
      await _verifyDescriptorSignature(
        descriptor: descriptor,
        publicKeyId: publicKeyId,
        publicKeyBase64: publicKeyBase64,
      );
    }

    final candidate = DesktopUpdaterReleaseCandidate(
      version: descriptor.version,
      buildNumber: descriptor.buildNumber,
      generatedAt: descriptor.generatedAt,
      mandatory: item.mandatory,
      platform: descriptor.platform,
      artifactKind: descriptor.artifact.kind,
      artifactUrl: descriptor.artifact.url,
      artifactSha256: descriptor.artifact.sha256,
      artifactLength: descriptor.artifact.length,
    );
    _archiveUrl = archiveUrl;
    _currentVersion = version;
    _descriptor = descriptor;
    _candidate = candidate;
    return candidate;
  }

  @override
  Future<String> downloadAndStage(
    DesktopUpdaterReleaseCandidate candidate, {
    void Function(double progress)? onProgress,
  }) async {
    final archiveUrl = _archiveUrl;
    final currentVersion = _currentVersion;
    final descriptor = _descriptor;
    if (archiveUrl == null ||
        currentVersion == null ||
        descriptor == null ||
        !identical(candidate, _candidate)) {
      throw StateError('The selected desktop update is no longer active.');
    }

    final result = await _updater.downloadZipFirstUpdate(
      appArchiveUrl: archiveUrl,
      currentVersion: currentVersion,
      descriptor: descriptor,
      onProgress: (receivedBytes, totalBytes) {
        final expected = totalBytes ?? descriptor.artifact.length;
        if (expected <= 0) {
          return;
        }
        onProgress?.call((receivedBytes / expected).clamp(0, 1).toDouble());
      },
    );
    return result.stagingPath;
  }

  @override
  Future<void> install({
    required String stagingPath,
    required bool allowUnsignedMacOSUpdates,
  }) {
    return _updater.installUpdate(
      stagingPath: stagingPath,
      allowUnsignedMacOSUpdates: allowUnsignedMacOSUpdates,
    );
  }

  @override
  void dispose() {
    _clearSelection();
    if (_ownsClient) {
      _client.close();
    }
  }

  void _clearSelection() {
    _archiveUrl = null;
    _currentVersion = null;
    _descriptor = null;
    _candidate = null;
  }
}

void _requireSuccess(http.Response response, Uri uri) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Update metadata request failed with HTTP ${response.statusCode}.',
      uri: uri,
    );
  }
}

void _verifyDescriptorIdentity({
  required ReleaseDescriptor descriptor,
  required ReleaseIndexItem item,
  required String platform,
  required String channel,
}) {
  if (descriptor.version != item.version ||
      descriptor.buildNumber != item.buildNumber ||
      descriptor.platform != item.platform ||
      descriptor.channel != item.channel ||
      descriptor.packageId != 'dev.leynier.alera' ||
      descriptor.appName != 'Alera' ||
      descriptor.platform != platform ||
      descriptor.channel != channel) {
    throw const FormatException(
      'The release descriptor does not match its update index entry.',
    );
  }
}

Future<void> _verifyDescriptorSignature({
  required ReleaseDescriptor descriptor,
  required String publicKeyId,
  required String publicKeyBase64,
}) async {
  final signature = descriptor.signature;
  if (signature == null ||
      signature.algorithm != 'ed25519' ||
      signature.publicKeyId != publicKeyId ||
      signature.value.trim().isEmpty) {
    throw const FormatException(
      'The release descriptor does not contain the required signature.',
    );
  }

  late final List<int> publicKeyBytes;
  late final List<int> signatureBytes;
  try {
    publicKeyBytes = base64Decode(publicKeyBase64.trim());
    signatureBytes = base64Decode(signature.value);
  } on FormatException {
    throw const FormatException(
      'The release descriptor signature or public key is not valid base64.',
    );
  }
  final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
  final valid = await Ed25519().verify(
    descriptor.canonicalSignatureBytes(),
    signature: Signature(signatureBytes, publicKey: publicKey),
  );
  if (!valid) {
    throw const FormatException('The release descriptor signature is invalid.');
  }
}
