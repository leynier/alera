/// Utility functions for type casting dynamic values.
library;

/// Casts a dynamic value to `Map<String, dynamic>`.
///
/// If the value is already a `Map<String, dynamic>`, returns it as-is.
/// If the value is a Map with other key types, converts keys to strings.
/// Returns an empty map for null or non-map values.
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

/// Casts a dynamic value to a num.
///
/// Returns the value if it's already a num.
/// Attempts to parse the value if it's a String.
/// Returns null for null or non-numeric values.
num? asNum(dynamic value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}
