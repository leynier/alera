import 'configuration_document.dart';

const _absent = _Absent();

class _Absent {
  const _Absent();
}

enum ConfigurationChoice { local, remote }

class ConfigurationDifference {
  ConfigurationDifference(
    this.path,
    this.local,
    this.remote,
    this.conflict,
    this.choice,
  );
  final List<String> path;
  final Object? local;
  final Object? remote;
  final bool conflict;
  ConfigurationChoice? choice;
  Object? customResult;
  String get label => path.join(' / ');
  bool get localAbsent => identical(local, _absent);
  bool get remoteAbsent => identical(remote, _absent);
  Object? get result =>
      customResult ?? (choice == ConfigurationChoice.remote ? remote : local);
  bool get canRename =>
      (path.contains('agentProfiles') || path.contains('textActions')) &&
      (path.last == 'name' ||
          result is Map && (result as Map).containsKey('name'));
  void rename(String name) {
    customResult = path.last == 'name'
        ? name
        : {...jsonMap(result), 'name': name};
  }

  String display(Object? value) =>
      identical(value, _absent) ? '(Removed)' : value.toString();
}

class ConfigurationMerge {
  ConfigurationMerge({
    required ConfigurationDocument local,
    required ConfigurationDocument remote,
    ConfigurationDocument? base,
    this.ownedBlocks = const {'shared', 'desktop', 'mobile'},
  }) {
    _result =
        _walk(base?.json ?? _absent, local.json, remote.json, []) as JsonMap;
  }
  final Set<String> ownedBlocks;
  final differences = <ConfigurationDifference>[];
  late final JsonMap _result;
  bool get hasUnresolved => differences.any((d) => d.choice == null);
  void chooseAll(ConfigurationChoice choice) {
    for (final difference in differences) {
      difference.choice = choice;
      difference.customResult = null;
    }
  }

  ConfigurationDocument resolve() {
    if (hasUnresolved)
      throw StateError('Resolve every conflict before continuing.');
    final result = _copy(_result) as JsonMap;
    for (final difference in differences) {
      var parent = result;
      for (final segment in difference.path.take(difference.path.length - 1)) {
        parent = parent[segment] as JsonMap;
      }
      if (identical(difference.result, _absent)) {
        parent.remove(difference.path.last);
      } else {
        parent[difference.path.last] = _copy(difference.result);
      }
    }
    return ConfigurationDocument(result);
  }

  Object? _walk(
    Object? base,
    Object? local,
    Object? remote,
    List<String> path,
  ) {
    if (path.length == 1 && !ownedBlocks.contains(path.first))
      return _copy(remote);
    if (_equal(local, remote)) return _copy(local);
    if (local is Map &&
        remote is Map &&
        (base is Map || identical(base, _absent))) {
      final keys = <String>{
        ...local.keys.cast<String>(),
        ...remote.keys.cast<String>(),
        if (base is Map) ...base.keys.cast<String>(),
      }.toList()..sort();
      return <String, Object?>{
        for (final key in keys)
          key: _walk(_get(base, key), _get(local, key), _get(remote, key), [
            ...path,
            key,
          ]),
      }..removeWhere((_, value) => identical(value, _absent));
    }
    ConfigurationChoice? choice;
    if (identical(base, _absent)) {
      if (identical(local, _absent)) choice = ConfigurationChoice.remote;
      if (identical(remote, _absent)) choice = ConfigurationChoice.local;
    } else if (_equal(local, base)) {
      choice = ConfigurationChoice.remote;
    } else if (_equal(remote, base)) {
      choice = ConfigurationChoice.local;
    }
    differences.add(
      ConfigurationDifference(path, local, remote, choice == null, choice),
    );
    return _copy(local);
  }
}

Object? _get(Object? map, String key) =>
    map is Map && map.containsKey(key) ? map[key] : _absent;
bool _equal(Object? a, Object? b) =>
    identical(a, _absent) || identical(b, _absent)
    ? identical(a, b)
    : sameJson(a, b);
Object? _copy(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _copy(entry.value),
      }
    : value is List
    ? value.map(_copy).toList()
    : value;
