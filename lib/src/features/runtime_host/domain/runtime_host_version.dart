/// Compares Alera sidecar / runtime host version strings as semver cores.
///
/// Pre-release and build metadata are ignored for ordering. Unparseable values
/// compare as equal to themselves and lower than any parseable version.
int compareRuntimeHostVersions(String left, String right) {
  final a = _parseSemverCore(left);
  final b = _parseSemverCore(right);
  if (a == null && b == null) {
    return left.compareTo(right);
  }
  if (a == null) {
    return -1;
  }
  if (b == null) {
    return 1;
  }
  for (var i = 0; i < 3; i++) {
    final delta = a[i].compareTo(b[i]);
    if (delta != 0) {
      return delta;
    }
  }
  return 0;
}

bool isRuntimeHostVersionNewer(String candidate, String current) {
  return compareRuntimeHostVersions(candidate, current) > 0;
}

List<int>? _parseSemverCore(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final core = trimmed.split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 3) {
    return null;
  }
  final numbers = <int>[];
  for (final part in parts) {
    final parsed = int.tryParse(part);
    if (parsed == null || parsed < 0) {
      return null;
    }
    numbers.add(parsed);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}
