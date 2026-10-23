import 'package:dart_mappable/dart_mappable.dart';

/// Reads the retired `opencode2` AI Assist agent as `opencode`.
///
/// OpenCode v1 and OpenCode 2 used to be separate agents; both install as
/// `opencode` now. Stored settings and an older runtime may still name the
/// old key, which the generated enum decoder would reject. [agentKeys] name
/// fields holding one agent and [agentMapKeys] maps keyed by agent, where an
/// `opencode` entry already present wins over the retired one.
class const LegacyOpenCode2AgentHook({
  this.agentKeys = const <String>[],
  this.agentMapKeys = const <String>[],
}) extends MappingHook {
  static const String legacyKey = 'opencode2';
  static const String currentKey = 'opencode';

  final List<String> agentKeys;
  final List<String> agentMapKeys;

  @override
  Object? beforeDecode(Object? value) {
    if (value is! Map) {
      return value;
    }
    final needsAgent = agentKeys.any((key) => value[key] == legacyKey);
    final needsMap = agentMapKeys.any(
      (key) => value[key] is Map && (value[key] as Map).containsKey(legacyKey),
    );
    if (!needsAgent && !needsMap) {
      return value;
    }
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): switch (entry.key) {
          final String key
              when agentKeys.contains(key) && entry.value == legacyKey =>
            currentKey,
          final String key
              when agentMapKeys.contains(key) && entry.value is Map =>
            _rekey(entry.value as Map),
          _ => entry.value,
        },
    };
  }

  static Map<String, dynamic> _rekey(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{
      for (final entry in map.entries)
        if (entry.key != legacyKey) entry.key.toString(): entry.value,
    };
    if (map.containsKey(legacyKey)) {
      result.putIfAbsent(currentKey, () => map[legacyKey]);
    }
    return result;
  }
}
