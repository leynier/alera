enum SpeechProcessingLocation { thisDevice, pairedDevice, directProvider }

enum SpeechBackend {
  whisper,
  sherpaOnnx,
  systemOnDevice,
  systemOnline,
  openAiCompatible,
}

class SpeechModelSummary {
  const SpeechModelSummary({
    required this.id,
    required this.label,
    required this.installed,
  });

  final String id;
  final String label;
  final bool installed;

  factory SpeechModelSummary.fromJson(Map<String, Object?> json) =>
      SpeechModelSummary(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        installed: json['installed'] == true,
      );
}

class SpeechProviderSummary {
  const SpeechProviderSummary({
    required this.id,
    required this.label,
    required this.type,
    this.defaultModel,
    this.models = const <String>[],
  });

  final String id;
  final String label;
  final SpeechBackend type;
  final String? defaultModel;
  final List<String> models;

  factory SpeechProviderSummary.fromJson(Map<String, Object?> json) =>
      SpeechProviderSummary(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        type: SpeechBackend.values.firstWhere(
          (value) => value.name == json['type']?.toString(),
          orElse: () => SpeechBackend.openAiCompatible,
        ),
        defaultModel: json['defaultModel']?.toString(),
        models: json['models'] is List
            ? (json['models'] as List)
                  .map((value) => value.toString())
                  .toList(growable: false)
            : const <String>[],
      );
}

class SpeechBackendCapability {
  const SpeechBackendCapability({
    required this.location,
    required this.backend,
    this.streaming = false,
    this.batchFile = false,
    this.requiresNetwork = false,
    this.guaranteedOnDevice = false,
    this.locales = const <String>[],
    this.models = const <SpeechModelSummary>[],
    this.providerProfiles = const <SpeechProviderSummary>[],
  });

  final SpeechProcessingLocation location;
  final SpeechBackend backend;
  final bool streaming;
  final bool batchFile;
  final bool requiresNetwork;
  final bool guaranteedOnDevice;
  final List<String> locales;
  final List<SpeechModelSummary> models;
  final List<SpeechProviderSummary> providerProfiles;

  factory SpeechBackendCapability.fromJson(Map<String, Object?> json) {
    final rawModels = json['models'];
    final rawProfiles = json['providerProfiles'];
    return SpeechBackendCapability(
      location: SpeechProcessingLocation.values.firstWhere(
        (value) => value.name == json['location']?.toString(),
        orElse: () => SpeechProcessingLocation.pairedDevice,
      ),
      backend: SpeechBackend.values.firstWhere(
        (value) => value.name == json['backend']?.toString(),
        orElse: () => SpeechBackend.whisper,
      ),
      streaming: json['streaming'] == true,
      batchFile: json['batchFile'] == true,
      requiresNetwork: json['requiresNetwork'] == true,
      guaranteedOnDevice: json['guaranteedOnDevice'] == true,
      locales: json['locales'] is List
          ? (json['locales'] as List)
                .map((value) => value.toString())
                .toList(growable: false)
          : const <String>[],
      models: rawModels is List
          ? rawModels
                .map(
                  (value) => SpeechModelSummary.fromJson(
                    Map<String, Object?>.from(value as Map),
                  ),
                )
                .toList(growable: false)
          : const <SpeechModelSummary>[],
      providerProfiles: rawProfiles is List
          ? rawProfiles
                .map(
                  (value) => SpeechProviderSummary.fromJson(
                    Map<String, Object?>.from(value as Map),
                  ),
                )
                .toList(growable: false)
          : const <SpeechProviderSummary>[],
    );
  }
}

class SpeechCapabilities {
  const SpeechCapabilities({required this.platform, required this.backends});

  final String platform;
  final List<SpeechBackendCapability> backends;

  factory SpeechCapabilities.fromJson(Map<String, Object?> json) {
    final rawBackends = json['backends'];
    return SpeechCapabilities(
      platform: json['platform']?.toString() ?? 'unknown',
      backends: rawBackends is List
          ? rawBackends
                .map(
                  (value) => SpeechBackendCapability.fromJson(
                    Map<String, Object?>.from(value as Map),
                  ),
                )
                .toList(growable: false)
          : const <SpeechBackendCapability>[],
    );
  }

  bool supports(SpeechBackend backend) =>
      backends.any((capability) => capability.backend == backend);
}
