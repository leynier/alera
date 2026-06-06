import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String aleraManifestSignatureKey = 'signature';
const String aleraManifestSignatureAlgorithm = 'ed25519';

class AleraManifestSignature {
  const AleraManifestSignature({
    required this.algorithm,
    required this.publicKeyId,
    required this.signature,
  });

  factory AleraManifestSignature.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Manifest signature must be an object.');
    }
    final json = Map<String, Object?>.from(value);
    final algorithm = _requiredString(json, 'algorithm');
    if (algorithm != aleraManifestSignatureAlgorithm) {
      throw FormatException(
        'Unsupported manifest signature algorithm: $algorithm.',
      );
    }
    return AleraManifestSignature(
      algorithm: algorithm,
      publicKeyId: _requiredString(json, 'publicKeyId'),
      signature: _requiredString(json, 'signature'),
    );
  }

  final String algorithm;
  final String publicKeyId;
  final String signature;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'algorithm': algorithm,
      'publicKeyId': publicKeyId,
      'signature': signature,
    };
  }
}

Future<bool> verifyAleraManifestSignature({
  required String manifestJson,
  required String publicKeyBase64,
}) async {
  if (publicKeyBase64.trim().isEmpty) {
    throw const FormatException('A manifest public key is required.');
  }

  final decoded = jsonDecode(manifestJson);
  if (decoded is! Map) {
    throw const FormatException('Update manifest must be a JSON object.');
  }
  final manifest = Map<String, Object?>.from(decoded);
  final signature = AleraManifestSignature.fromJson(
    manifest[aleraManifestSignatureKey],
  );
  final signatureBytes = base64Decode(signature.signature);
  final publicKeyBytes = base64Decode(publicKeyBase64);
  final payload = canonicalAleraManifestPayload(manifest);
  final algorithm = Ed25519();
  return algorithm.verify(
    utf8.encode(payload),
    signature: Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    ),
  );
}

Future<Map<String, Object?>> signAleraManifest({
  required Map<String, Object?> manifest,
  required String privateKeyBase64,
  required String publicKeyBase64,
  required String publicKeyId,
}) async {
  final normalizedPublicKeyId = publicKeyId.trim();
  if (normalizedPublicKeyId.isEmpty) {
    throw const FormatException('publicKeyId must be a non-empty string.');
  }
  final unsigned = Map<String, Object?>.from(manifest)
    ..remove(aleraManifestSignatureKey);
  final privateKeyBytes = base64Decode(privateKeyBase64);
  final publicKeyBytes = base64Decode(publicKeyBase64);
  final keyPair = SimpleKeyPairData(
    privateKeyBytes,
    publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );
  final signature = await Ed25519().sign(
    utf8.encode(canonicalAleraManifestPayload(unsigned)),
    keyPair: keyPair,
  );
  return <String, Object?>{
    ...unsigned,
    aleraManifestSignatureKey: AleraManifestSignature(
      algorithm: aleraManifestSignatureAlgorithm,
      publicKeyId: normalizedPublicKeyId,
      signature: base64Encode(signature.bytes),
    ).toJson(),
  };
}

String canonicalAleraManifestPayload(Map<String, Object?> manifest) {
  final unsigned = Map<String, Object?>.from(manifest)
    ..remove(aleraManifestSignatureKey);
  return jsonEncode(_canonicalValue(unsigned));
}

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final sorted = <String, Object?>{};
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      sorted[key] = _canonicalValue(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonicalValue(item)];
  }
  if (value is Uint8List) {
    return base64Encode(value);
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}
