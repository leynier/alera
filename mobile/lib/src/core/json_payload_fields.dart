import 'dart:convert';

/// Typed field access for runtime protocol payloads. Required accessors throw
/// [FormatException] so malformed payloads fail loudly at the parsing
/// boundary instead of deep inside the UI.
extension JsonPayloadFields on Map<String, Object?> {
  String requiredString(String key) {
    final value = this[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw FormatException('$key is required');
  }

  String? optionalString(String key) {
    final value = this[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  int requiredInt(String key) {
    final value = this[key];
    if (value is int) {
      return value;
    }
    throw FormatException('$key is required');
  }

  /// A count that only means anything above zero, so a host that omits the
  /// field and one that sends a placeholder are read the same way.
  int? optionalPositiveInt(String key) {
    final value = this[key];
    if (value is int && value > 0) {
      return value;
    }
    return null;
  }

  DateTime? optionalDateTime(String key) {
    final value = optionalString(key);
    if (value == null) {
      return null;
    }
    return DateTime.parse(value);
  }

  List<Object?> objectList(String key) {
    final value = this[key];
    if (value is List<Object?>) {
      return value;
    }
    if (value is List) {
      return List<Object?>.from(value);
    }
    return const <Object?>[];
  }

  List<String> stringList(String key) {
    return <String>[
      for (final item in objectList(key))
        if (item is String) item,
    ];
  }

  Map<String, Object?> mapValue(String key) {
    return asJsonMap(this[key]);
  }

  List<int> base64Bytes(String key) {
    final value = this[key];
    if (value is! String || value.isEmpty) {
      return const <int>[];
    }
    return base64Decode(value);
  }
}

Map<String, Object?> asJsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}
