import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'bounded_update_transport.dart';

class const DesktopUpdateIndexNotFound() implements Exception;

class const DesktopUpdaterReleaseCandidate({
  required final String version,
  required final int? buildNumber,
  required final DateTime generatedAt,
  required final bool mandatory,
  required final String platform,
  required final String artifactKind,
  required final Uri artifactUrl,
  required final String artifactSha256,
  required final int artifactLength,
});

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
  DesktopUpdaterBackend({
    DesktopUpdater? updater,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
    this.artifactTimeout = const Duration(seconds: 30),
    @visibleForTesting
    FutureOr<void> Function()? afterTransportCancelForTesting,
  }) : _updater = updater ?? DesktopUpdater(),
       _providedClient = client,
       _client = client ?? http.Client(),
       // Keep this testing seam separate from the runtime state.
       // ignore: prefer_initializing_formals
       _afterTransportCancel = afterTransportCancelForTesting {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    if (artifactTimeout <= Duration.zero) {
      throw ArgumentError.value(
        artifactTimeout,
        'artifactTimeout',
        'must be positive',
      );
    }
  }

  final DesktopUpdater _updater;
  final http.Client? _providedClient;
  http.Client _client;
  final Duration requestTimeout;

  /// Header timeout and maximum idle gap between artifact body chunks.
  /// Active transfers may exceed this duration while bytes continue arriving.
  final Duration artifactTimeout;
  final FutureOr<void> Function()? _afterTransportCancel;
  BoundedUpdateTransport? _activeTransport;
  bool _disposed = false;
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
    _ensureActive();
    _clearSelection();
    final version = DesktopVersionInfo.fromParts(
      versionName: currentVersion,
      buildNumber: currentBuildNumber,
    );
    final indexResponse = await _get(archiveUrl);
    _ensureActive();
    if (indexResponse.statusCode == HttpStatus.notFound) {
      _clearSelection();
      throw const DesktopUpdateIndexNotFound();
    }
    _requireSuccess(indexResponse, archiveUrl);
    _checkMetadataSize(indexResponse, archiveUrl);
    final index = ReleaseIndex.fromJson(_decodeMetadata(indexResponse));
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

    final descriptorResponse = await _get(item.release);
    _ensureActive();
    _requireSuccess(descriptorResponse, item.release);
    _checkMetadataSize(descriptorResponse, item.release);
    final descriptor = ReleaseDescriptor.fromJson(
      _decodeMetadata(descriptorResponse),
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
      _ensureActive();
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
    if (_disposed) {
      throw StateError('The desktop updater backend has been disposed.');
    }
    final archiveUrl = _archiveUrl;
    final currentVersion = _currentVersion;
    final descriptor = _descriptor;
    if (archiveUrl == null ||
        currentVersion == null ||
        descriptor == null ||
        !identical(candidate, _candidate)) {
      throw StateError('The selected desktop update is no longer active.');
    }
    if (_activeTransport != null) {
      throw StateError('An update download is already in progress.');
    }

    final transport = BoundedUpdateTransport(
      maxBytes: descriptor.artifact.length,
      timeout: artifactTimeout,
    );
    _activeTransport = transport;
    late final String stagingPath;
    try {
      final result = await http.runWithClient(
        () => _updater.downloadZipFirstUpdate(
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
        ),
        () => transport,
      );
      stagingPath = result.stagingPath;
    } finally {
      try {
        await transport.cancel();
        await _afterTransportCancel?.call();
      } finally {
        transport.close();
        if (identical(_activeTransport, transport)) {
          _activeTransport = null;
        }
      }
    }
    if (_disposed) {
      await _deleteStagedResult(stagingPath, descriptor);
      throw StateError('The desktop updater backend has been disposed.');
    }
    return stagingPath;
  }

  @override
  Future<void> install({
    required String stagingPath,
    required bool allowUnsignedMacOSUpdates,
  }) {
    if (_disposed) {
      throw StateError('The desktop updater backend has been disposed.');
    }
    return _updater.installUpdate(
      stagingPath: stagingPath,
      allowUnsignedMacOSUpdates: allowUnsignedMacOSUpdates,
    );
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('The desktop updater backend has been disposed.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clearSelection();
    final transport = _activeTransport;
    if (transport != null) {
      unawaited(transport.cancel());
    }
    if (_providedClient == null) {
      _client.close();
    }
  }

  Future<void> _deleteStagedResult(
    String stagingPath,
    ReleaseDescriptor descriptor,
  ) async {
    final staged = Directory(stagingPath);
    final isMacOSApp =
        descriptor.platform == 'macos' &&
        (descriptor.artifact.kind == 'zip' ||
            descriptor.artifact.kind == 'dmg');
    final root = isMacOSApp ? staged.parent : staged;
    if (!p.basename(root.path).startsWith('desktop_updater_stage_')) {
      return;
    }
    try {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } on Object {
      // The updater package already performs the same best-effort cleanup on
      // errors.
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _readMetadata(uri).timeout(requestTimeout);
    } on TimeoutException {
      // A timed-out metadata request must not leave the recurring scheduler
      // waiting forever. The owned client is closed to tear down its socket;
      // replace it so a later foreground check can start cleanly.
      if (_providedClient == null && !_disposed) {
        _client.close();
        _client = http.Client();
      }
      _clearSelection();
      throw HttpException(
        'Update metadata request timed out after $requestTimeout.',
        uri: uri,
      );
    }
  }

  Future<http.Response> _readMetadata(Uri uri) async {
    final streamed = await _client.send(http.Request('GET', uri));
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in streamed.stream) {
      length += chunk.length;
      if (length > _maxUpdateMetadataBytes) {
        throw FormatException(
          'Update metadata from $uri exceeds the '
          '$_maxUpdateMetadataBytes byte limit.',
        );
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(
      bytes.takeBytes(),
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  void _clearSelection() {
    _archiveUrl = null;
    _currentVersion = null;
    _descriptor = null;
    _candidate = null;
  }
}

const int _maxUpdateMetadataBytes = 1024 * 1024;

void _checkMetadataSize(http.Response response, Uri uri) {
  if (response.bodyBytes.length > _maxUpdateMetadataBytes) {
    throw FormatException(
      'Update metadata from $uri exceeds the $_maxUpdateMetadataBytes byte limit.',
    );
  }
}

Map<String, dynamic> _decodeMetadata(http.Response response) {
  return jsonDecode(response.body) as Map<String, dynamic>;
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
  final publicKey = SimplePublicKey(publicKeyBytes, type: .ed25519);
  final valid = await Ed25519().verify(
    descriptor.canonicalSignatureBytes(),
    signature: Signature(signatureBytes, publicKey: publicKey),
  );
  if (!valid) {
    throw const FormatException('The release descriptor signature is invalid.');
  }
}
