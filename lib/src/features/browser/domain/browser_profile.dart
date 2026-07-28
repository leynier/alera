const String defaultBrowserProfileId = 'default';

enum BrowserProfileKind { defaultProfile, isolated, imported }

enum BrowserImportSourceFamily {
  chrome,
  edge,
  arc,
  brave,
  comet,
  helium,
  firefox,
  safari,
  manual,
}

final class BrowserProfileSource {
  const BrowserProfileSource({
    required this.family,
    required this.importedAt,
    this.profileName,
  });

  factory BrowserProfileSource.fromJson(Map<String, Object?> json) {
    final importedAt = DateTime.tryParse(json['importedAt'] as String? ?? '');
    if (importedAt == null) {
      throw const FormatException('Browser Profile Source Date Is Invalid.');
    }
    return BrowserProfileSource(
      family: BrowserImportSourceFamily.values.firstWhere(
        (family) => family.name == json['family'],
        orElse: () => BrowserImportSourceFamily.manual,
      ),
      profileName: _nonEmptyBrowserProfileString(json['profileName']),
      importedAt: importedAt.toUtc(),
    );
  }

  final BrowserImportSourceFamily family;
  final String? profileName;
  final DateTime importedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'family': family.name,
    if (profileName != null) 'profileName': profileName,
    'importedAt': importedAt.toUtc().toIso8601String(),
  };
}

final class BrowserProfile {
  const BrowserProfile({
    required this.id,
    required this.label,
    required this.kind,
    required this.createdAt,
    this.persistent = true,
    this.updatedAt,
    this.source,
  });

  factory BrowserProfile.fromJson(Map<String, Object?> json) {
    final id = _nonEmptyBrowserProfileString(json['id']);
    final label = _nonEmptyBrowserProfileString(json['label']);
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id == null || label == null || createdAt == null) {
      throw const FormatException('Browser Profile Payload Is Invalid.');
    }
    final source = json['source'];
    return BrowserProfile(
      id: id,
      label: label,
      kind: BrowserProfileKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => id == defaultBrowserProfileId
            ? BrowserProfileKind.defaultProfile
            : BrowserProfileKind.isolated,
      ),
      createdAt: createdAt.toUtc(),
      persistent: json['persistent'] != false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
      source: source is Map
          ? BrowserProfileSource.fromJson(Map<String, Object?>.from(source))
          : null,
    );
  }

  final String id;
  final String label;
  final BrowserProfileKind kind;
  final DateTime createdAt;
  final bool persistent;
  final DateTime? updatedAt;
  final BrowserProfileSource? source;

  bool get isDefault => id == defaultBrowserProfileId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'kind': kind.name,
    'persistent': persistent,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    if (source != null) 'source': source!.toJson(),
  };
}

String? _nonEmptyBrowserProfileString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
