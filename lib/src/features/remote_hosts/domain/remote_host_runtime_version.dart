/// How a host's Alera runtime version compares with this app's runtime.
enum RuntimeVersionRelation { older, same, newer, unknown }

/// Compares the numeric `major.minor.patch` prefix of two versions, ignoring
/// pre-release and build suffixes. Only [RuntimeVersionRelation.older] offers
/// an update, so a development hub never proposes a downgrade.
RuntimeVersionRelation runtimeVersionRelation(String? hub, String? satellite) {
  final hubParts = _numericParts(hub);
  final satelliteParts = _numericParts(satellite);
  if (hubParts == null || satelliteParts == null) {
    return RuntimeVersionRelation.unknown;
  }
  final length = hubParts.length > satelliteParts.length
      ? hubParts.length
      : satelliteParts.length;
  for (var index = 0; index < length; index++) {
    final hubPart = index < hubParts.length ? hubParts[index] : 0;
    final satellitePart = index < satelliteParts.length
        ? satelliteParts[index]
        : 0;
    if (satellitePart < hubPart) {
      return RuntimeVersionRelation.older;
    }
    if (satellitePart > hubPart) {
      return RuntimeVersionRelation.newer;
    }
  }
  return RuntimeVersionRelation.same;
}

final RegExp _versionPrefix = RegExp(r'^v?(\d+(?:\.\d+)*)');

List<int>? _numericParts(String? version) {
  final match = _versionPrefix.firstMatch(version?.trim() ?? '');
  if (match == null) {
    return null;
  }
  return <int>[for (final part in match.group(1)!.split('.')) int.parse(part)];
}
