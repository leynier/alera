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

final class const BrowserProfileSource({
  required final BrowserImportSourceFamily family,
  required final DateTime importedAt,
  final String? profileName,
}) {
  factory fromJson(Map<String, Object?> json) {
    final importedAt = DateTime.tryParse(json['importedAt'] as String? ?? '');
    if (importedAt == null) {
      throw const FormatException('Browser profile source date is invalid.');
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

  Map<String, Object?> toJson() => <String, Object?>{
    'family': family.name,
    if (profileName != null) 'profileName': profileName,
    'importedAt': importedAt.toUtc().toIso8601String(),
  };
}

final class const BrowserProfile({
  required final String id,
  required final String label,
  required final BrowserProfileKind kind,
  required final DateTime createdAt,
  final bool persistent = true,
  final DateTime? updatedAt,
  final BrowserProfileSource? source,
}) {
  factory fromJson(Map<String, Object?> json) {
    final id = _nonEmptyBrowserProfileString(json['id']);
    final label = _nonEmptyBrowserProfileString(json['label']);
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id == null || label == null || createdAt == null) {
      throw const FormatException('Browser profile payload is invalid.');
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
