import 'package:path/path.dart' as p;

final class NativeHelperDerivation({
  required final String sourceArchiveRoot,
  required final String sourceSubdirectory,
  required final String packageDirectory,
  required final String product,
  required final String buildOutput,
  required final List<String> architectures,
  required final String dependencyLockPath,
  required final String dependencyLockSha256,
  required final String patchPath,
  required final String patchSha256,
  required final List<NativeHelperPatchTarget> patchTargets,
  required final List<NativeHelperDependency> dependencies,
}) {
  factory fromJson(Object? value, {required String assetId}) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$assetId derivation must be a JSON object.');
    }
    if (_requiredString(value, 'type') != 'swift-package') {
      throw FormatException('$assetId derivation type must be swift-package.');
    }
    final rawArchitectures = value['architectures'];
    if (rawArchitectures is! List<Object?> || rawArchitectures.isEmpty) {
      throw FormatException(
        '$assetId derivation architectures must be a non-empty array.',
      );
    }
    final architectures = <String>{};
    for (final architecture in rawArchitectures) {
      if (architecture is! String ||
          !const <String>{'arm64', 'x86_64'}.contains(architecture) ||
          !architectures.add(architecture)) {
        throw FormatException(
          '$assetId derivation contains an invalid architecture.',
        );
      }
    }
    final rawTargets = value['patchTargets'];
    if (rawTargets is! List<Object?> || rawTargets.isEmpty) {
      throw FormatException(
        '$assetId derivation patchTargets must be a non-empty array.',
      );
    }
    final rawDependencies = value['dependencies'];
    if (rawDependencies is! List<Object?> || rawDependencies.isEmpty) {
      throw FormatException(
        '$assetId derivation dependencies must be a non-empty array.',
      );
    }
    return NativeHelperDerivation(
      sourceArchiveRoot: _requiredRelativePath(value, 'sourceArchiveRoot'),
      sourceSubdirectory: _requiredRelativePath(value, 'sourceSubdirectory'),
      packageDirectory: _requiredRelativePath(value, 'packageDirectory'),
      product: _requiredString(value, 'product'),
      buildOutput: _requiredRelativePath(value, 'buildOutput'),
      architectures: .unmodifiableOf(architectures),
      dependencyLockPath: _requiredRelativePath(value, 'dependencyLockPath'),
      dependencyLockSha256: _requiredSha256(
        value,
        'dependencyLockSha256',
        assetId,
      ),
      patchPath: _requiredRelativePath(value, 'patchPath'),
      patchSha256: _requiredSha256(value, 'patchSha256', assetId),
      patchTargets: .unmodifiableOf(
        rawTargets.map(
          (target) =>
              NativeHelperPatchTarget.fromJson(target, assetId: assetId),
        ),
      ),
      dependencies: .unmodifiableOf(
        rawDependencies.map(
          (dependency) =>
              NativeHelperDependency.fromJson(dependency, assetId: assetId),
        ),
      ),
    );
  }

  Map<String, Object?> bundleJson() => <String, Object?>{
    'type': 'swift-package',
    'sourceArchiveRoot': sourceArchiveRoot,
    'sourceSubdirectory': sourceSubdirectory,
    'packageDirectory': packageDirectory,
    'product': product,
    'buildOutput': buildOutput,
    'architectures': architectures,
    'dependencyLockPath': dependencyLockPath,
    'dependencyLockSha256': dependencyLockSha256,
    'patchPath': patchPath,
    'patchSha256': patchSha256,
    'patchTargets': <Object?>[
      for (final target in patchTargets) target.bundleJson(),
    ],
    'dependencies': <Object?>[
      for (final dependency in dependencies) dependency.bundleJson(),
    ],
  };
}

final class NativeHelperPatchTarget({
  required final String path,
  required final String beforeSha256,
  required final String afterSha256,
}) {
  factory fromJson(Object? value, {required String assetId}) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$assetId patch target must be a JSON object.');
    }
    return NativeHelperPatchTarget(
      path: _requiredRelativePath(value, 'path'),
      beforeSha256: _requiredSha256(value, 'beforeSha256', assetId),
      afterSha256: _requiredSha256(value, 'afterSha256', assetId),
    );
  }

  Map<String, Object?> bundleJson() => <String, Object?>{
    'path': path,
    'beforeSha256': beforeSha256,
    'afterSha256': afterSha256,
  };
}

final class NativeHelperDependency({
  required final String id,
  required final Uri sourceUrl,
  required final String sourceSha256,
  required final String sourceCommit,
  required final String archiveRoot,
  required final String destination,
  required final String license,
  required final String licensePath,
}) {
  factory fromJson(Object? value, {required String assetId}) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$assetId dependency must be a JSON object.');
    }
    final id = _requiredString(value, 'id');
    return NativeHelperDependency(
      id: id,
      sourceUrl: _requiredHttpsUri(value, 'sourceUrl', '$assetId/$id'),
      sourceSha256: _requiredSha256(value, 'sourceSha256', '$assetId/$id'),
      sourceCommit: _requiredCommit(value, 'sourceCommit', '$assetId/$id'),
      archiveRoot: _requiredRelativePath(value, 'archiveRoot'),
      destination: _requiredRelativePath(value, 'destination'),
      license: _requiredString(value, 'license'),
      licensePath: _requiredRelativePath(value, 'licensePath'),
    );
  }

  Map<String, Object?> bundleJson() => <String, Object?>{
    'id': id,
    'sourceUrl': sourceUrl.toString(),
    'sourceSha256': sourceSha256,
    'sourceCommit': sourceCommit,
    'archiveRoot': archiveRoot,
    'destination': destination,
    'license': license,
    'licensePath': licensePath,
  };
}

String _requiredString(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('$key must be a non-empty string.');
}

Uri _requiredHttpsUri(Map<String, Object?> object, String key, String owner) {
  final source = Uri.tryParse(_requiredString(object, key));
  if (source == null || source.scheme != 'https' || source.host.isEmpty) {
    throw FormatException('$owner $key must use HTTPS.');
  }
  return source;
}

String _requiredRelativePath(Map<String, Object?> object, String key) {
  final value = _requiredString(object, key);
  final normalized = p.posix.normalize(value);
  if (p.posix.isAbsolute(value) ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    throw FormatException('$key must stay inside its declared root.');
  }
  return normalized;
}

String _requiredSha256(
  Map<String, Object?> object,
  String key,
  String assetId,
) {
  final value = _requiredString(object, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$assetId $key must be a lowercase SHA-256.');
  }
  return value;
}

String _requiredCommit(
  Map<String, Object?> object,
  String key,
  String assetId,
) {
  final value = _requiredString(object, key);
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    throw FormatException('$assetId $key must be a full Git commit hash.');
  }
  return value;
}
