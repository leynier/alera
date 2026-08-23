enum SpeechModelRuntime { whisperCpp, sherpaOnnx }

enum SpeechRecognitionMode { batch, streaming }

enum SpeechExecutionProvider { auto, cpu, coreMl, qnnHtp, nnApi }

class SpeechModelArtifact {
  const SpeechModelArtifact({
    required this.id,
    required this.relativePath,
    required this.uri,
    required this.sha256,
    required this.sizeBytes,
  });

  final String id;
  final String relativePath;
  final String uri;
  final String sha256;
  final int sizeBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'relativePath': relativePath,
    'uri': uri,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };

  factory SpeechModelArtifact.fromJson(Map<String, Object?> json) =>
      SpeechModelArtifact(
        id: _requiredString(json, 'id'),
        relativePath: _requiredString(json, 'relativePath'),
        uri: _requiredString(json, 'uri'),
        sha256: _requiredString(json, 'sha256'),
        sizeBytes: _requiredInt(json, 'sizeBytes'),
      );
}

class SpeechModelDescriptor {
  SpeechModelDescriptor({
    required this.id,
    required this.label,
    required this.description,
    required this.runtime,
    required this.mode,
    required List<SpeechModelArtifact> artifacts,
    this.languages = const <String>[],
    this.supportsAutomaticLanguageDetection = false,
    this.supportsInitialPrompt = false,
    this.supportedProviders = const <SpeechExecutionProvider>{
      SpeechExecutionProvider.cpu,
    },
    SpeechExecutionProvider? preferredProvider,
    this.storageVersion = 1,
  }) : artifacts = List<SpeechModelArtifact>.unmodifiable(artifacts),
       preferredProvider =
           preferredProvider ??
           (supportedProviders.contains(SpeechExecutionProvider.auto)
               ? SpeechExecutionProvider.auto
               : SpeechExecutionProvider.cpu) {
    _validate();
  }

  final String id;
  final String label;
  final String description;
  final SpeechModelRuntime runtime;
  final SpeechRecognitionMode mode;
  final List<SpeechModelArtifact> artifacts;
  final List<String> languages;
  final bool supportsAutomaticLanguageDetection;
  final bool supportsInitialPrompt;
  final Set<SpeechExecutionProvider> supportedProviders;
  final SpeechExecutionProvider preferredProvider;
  final int storageVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'description': description,
    'runtime': runtime.name,
    'mode': mode.name,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'languages': languages,
    'supportsAutomaticLanguageDetection': supportsAutomaticLanguageDetection,
    'supportsInitialPrompt': supportsInitialPrompt,
    'supportedProviders': supportedProviders
        .map((value) => value.name)
        .toList(),
    'preferredProvider': preferredProvider.name,
    'storageVersion': storageVersion,
  };

  factory SpeechModelDescriptor.fromJson(Map<String, Object?> json) {
    final rawArtifacts = json['artifacts'];
    final rawProviders = json['supportedProviders'];
    return SpeechModelDescriptor(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      description: _requiredString(json, 'description'),
      runtime: SpeechModelRuntime.values.byName(
        _requiredString(json, 'runtime'),
      ),
      mode: SpeechRecognitionMode.values.byName(_requiredString(json, 'mode')),
      artifacts: rawArtifacts is List
          ? rawArtifacts
                .map(
                  (value) => SpeechModelArtifact.fromJson(
                    Map<String, Object?>.from(value as Map),
                  ),
                )
                .toList()
          : const <SpeechModelArtifact>[],
      languages: _stringList(json['languages']),
      supportsAutomaticLanguageDetection:
          json['supportsAutomaticLanguageDetection'] == true,
      supportsInitialPrompt: json['supportsInitialPrompt'] == true,
      supportedProviders: rawProviders is List
          ? rawProviders
                .map(
                  (value) =>
                      SpeechExecutionProvider.values.byName(value.toString()),
                )
                .toSet()
          : const <SpeechExecutionProvider>{SpeechExecutionProvider.cpu},
      preferredProvider: json['preferredProvider'] == null
          ? null
          : SpeechExecutionProvider.values.byName(
              json['preferredProvider'].toString(),
            ),
      storageVersion: _requiredInt(json, 'storageVersion'),
    );
  }

  void _validate() {
    if (id.trim().isEmpty || label.trim().isEmpty) {
      throw ArgumentError('Speech models require an id and label.');
    }
    if (artifacts.isEmpty) {
      throw ArgumentError('Speech models require at least one artifact.');
    }
    if (storageVersion < 1) {
      throw ArgumentError.value(storageVersion, 'storageVersion');
    }
    for (final artifact in artifacts) {
      if (artifact.id.trim().isEmpty || artifact.sizeBytes < 0) {
        throw ArgumentError('Speech model artifacts must have valid metadata.');
      }
      final path = artifact.relativePath.replaceAll('\\', '/');
      if (path.isEmpty ||
          path.startsWith('/') ||
          path.split('/').contains('..')) {
        throw ArgumentError.value(
          artifact.relativePath,
          'relativePath',
          'Artifact paths must stay inside the model directory.',
        );
      }
    }
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key]?.toString();
  if (value == null || value.trim().isEmpty) {
    throw FormatException('Missing speech model field: $key');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing speech model field: $key');
}

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const <String>[];
