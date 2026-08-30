enum SpeechProcessingLocation { thisDevice, pairedDevice, directProvider }

enum SpeechBackend {
  whisper,
  sherpaOnnx,
  systemOnDevice,
  systemOnline,
  openAiCompatible,
}

class const SpeechModelSummary({
  required final String id,
  required final String label,
  required final bool installed,
}) {
  factory fromJson(Map<String, Object?> json) => SpeechModelSummary(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    installed: json['installed'] == true,
  );
}

class const SpeechProviderSummary({
  required final String id,
  required final String label,
  required final SpeechBackend type,
  final String? defaultModel,
  final List<String> models = const <String>[],
}) {
  factory fromJson(Map<String, Object?> json) => SpeechProviderSummary(
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

class const SpeechBackendCapability({
  required final SpeechProcessingLocation location,
  required final SpeechBackend backend,
  final bool streaming = false,
  final bool batchFile = false,
  final bool requiresNetwork = false,
  final bool guaranteedOnDevice = false,
  final List<String> locales = const <String>[],
  final List<SpeechModelSummary> models = const <SpeechModelSummary>[],
  final List<SpeechProviderSummary> providerProfiles =
      const <SpeechProviderSummary>[],
}) {
  factory fromJson(Map<String, Object?> json) {
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

class const SpeechCapabilities({
  required final String platform,
  required final List<SpeechBackendCapability> backends,
}) {
  factory fromJson(Map<String, Object?> json) {
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
