import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? 'public/app-archive.json' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path does not exist.');
    exit(1);
  }

  final privateKey = _requiredEnv('ALERA_UPDATE_MANIFEST_PRIVATE_KEY');
  final publicKey = _requiredEnv('ALERA_UPDATE_MANIFEST_PUBLIC_KEY');
  final publicKeyId = Platform
      .environment['ALERA_UPDATE_MANIFEST_PUBLIC_KEY_ID']
      ?.trim();

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    stderr.writeln('$path must contain a JSON object.');
    exit(1);
  }

  final signed = await signAleraManifest(
    manifest: Map<String, Object?>.from(decoded),
    privateKeyBase64: privateKey,
    publicKeyBase64: publicKey,
    publicKeyId: publicKeyId == null || publicKeyId.isEmpty
        ? 'alera-release-v1'
        : publicKeyId,
  );
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(signed));
  stdout.writeln('Signed $path');
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('$name must be set.');
    exit(64);
  }
  return value;
}
